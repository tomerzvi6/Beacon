"""Medical document pipeline: parse, list, soft-delete, archive, privacy."""
import base64
import json
import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context, require_module_access, require_roles
from parser_api.middleware import limiter
from parser_api.services.grok_parser import GrokParser
from parser_api.services.name_detector import should_flag
from parser_api.services.ocr_service import OCRService
from parser_api.services.storage_service import get_storage_service
from shared.models import AuditLog, Document, HouseholdMember, Task
from shared.schemas import (
    DocumentListParams,
    DocumentOut,
    DocumentPatchIn,
    ParseResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/documents", tags=["documents"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _encode_cursor(created_at: datetime, doc_id: uuid.UUID) -> str:
    return base64.b64encode(
        json.dumps([created_at.isoformat(), str(doc_id)]).encode()
    ).decode()


def _decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        data = json.loads(base64.b64decode(cursor))
        return datetime.fromisoformat(data[0]), uuid.UUID(data[1])
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid pagination cursor")


def _caller_role(session: Session, user: TokenPayload) -> str | None:
    member = session.scalar(
        select(HouseholdMember).where(
            HouseholdMember.household_id == uuid.UUID(user.household_id),
            HouseholdMember.user_id == uuid.UUID(user.user_id),
        )
    )
    return member.role if member else None


def _assert_document_readable(doc: Document, role: str | None, user: TokenPayload) -> None:
    """Central authorization gate for every action that exposes a document's
    contents (view, parse, patch, ...). Caregivers cannot read another
    member's private document — the household match alone is not enough.
    """
    if doc.is_private and role == "caregiver" and str(doc.uploaded_by) != user.user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot access private document")


# ---------------------------------------------------------------------------
# List / archive
# ---------------------------------------------------------------------------


@router.get("/", response_model=list[DocumentOut])
def list_documents(
    category: str | None = Query(default=None),
    from_date: datetime | None = Query(default=None),
    to_date: datetime | None = Query(default=None),
    uploaded_by: uuid.UUID | None = Query(default=None),
    q: str | None = Query(default=None),
    include_deleted: bool = Query(default=False),
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = Query(default=None),
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
    _module: TokenPayload = Depends(require_module_access("medicalVault", 1)),
) -> list[DocumentOut]:
    role = _caller_role(session, user)

    stmt = select(Document).where(
        Document.household_id == uuid.UUID(user.household_id)
    )

    # Only the patient/co-owner may browse soft-deleted documents (mirrors
    # the dedicated /trash route's role gate) — a caregiver passing
    # include_deleted=true is silently limited to the non-deleted view.
    if not include_deleted or role not in ("patient", "co_owner"):
        stmt = stmt.where(Document.deleted_at.is_(None))

    # Caregivers cannot see private documents uploaded by others
    if role == "caregiver":
        stmt = stmt.where(
            or_(
                Document.is_private.is_(False),
                Document.uploaded_by == uuid.UUID(user.user_id),
            )
        )

    if category:
        stmt = stmt.where(Document.category == category)
    if from_date:
        stmt = stmt.where(Document.created_at >= from_date)
    if to_date:
        stmt = stmt.where(Document.created_at <= to_date)
    if uploaded_by:
        stmt = stmt.where(Document.uploaded_by == uploaded_by)
    if q:
        from sqlalchemy import func
        stmt = stmt.where(
            func.to_tsvector("simple",
                func.coalesce(Document.parsed_summary_simple_he, "") + " " +
                func.coalesce(Document.filename, "")
            ).op("@@")(func.plainto_tsquery("simple", q))
        )

    if cursor:
        cursor_dt, cursor_id = _decode_cursor(cursor)
        stmt = stmt.where(
            or_(
                Document.created_at < cursor_dt,
                and_(Document.created_at == cursor_dt, Document.id < cursor_id),
            )
        )

    stmt = stmt.order_by(Document.created_at.desc(), Document.id.desc()).limit(limit)
    docs = session.scalars(stmt).all()
    return [DocumentOut.model_validate(d) for d in docs]


# ---------------------------------------------------------------------------
# Soft delete
# ---------------------------------------------------------------------------


@router.delete("/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_document(
    document_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
    _module: TokenPayload = Depends(require_module_access("medicalVault", 2)),
) -> None:
    role = _caller_role(session, user)
    doc = session.scalar(
        select(Document).where(
            Document.id == uuid.UUID(document_id),
            Document.household_id == uuid.UUID(user.household_id),
            Document.deleted_at.is_(None),
        )
    )
    if doc is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    # Phase 9.4: caregivers can only soft-delete documents they uploaded
    # themselves. Patient + co_owner can delete anything in the
    # household; the existing trash/restore flow lets them recover.
    if role == "caregiver" and str(doc.uploaded_by) != user.user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Caregivers may only delete documents they uploaded",
        )

    doc.deleted_at = datetime.now(tz=timezone.utc)
    doc.deleted_by = uuid.UUID(user.user_id)
    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="soft_delete_document",
            target_table="documents",
            target_id=doc.id,
            household_id=doc.household_id,
        )
    )
    session.commit()


# ---------------------------------------------------------------------------
# Trash view
# ---------------------------------------------------------------------------


@router.get("/trash", response_model=list[DocumentOut])
def list_trash(
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = Query(default=None),
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(require_roles("patient", "co_owner")),
) -> list[DocumentOut]:
    stmt = select(Document).where(
        Document.household_id == uuid.UUID(user.household_id),
        Document.deleted_at.is_not(None),
    )
    if cursor:
        cursor_dt, cursor_id = _decode_cursor(cursor)
        stmt = stmt.where(
            or_(
                Document.deleted_at < cursor_dt,
                and_(Document.deleted_at == cursor_dt, Document.id < cursor_id),
            )
        )
    stmt = stmt.order_by(Document.deleted_at.desc(), Document.id.desc()).limit(limit)
    docs = session.scalars(stmt).all()
    return [DocumentOut.model_validate(d) for d in docs]


# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------


@router.post("/{document_id}/restore", response_model=DocumentOut)
def restore_document(
    document_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(require_roles("patient", "co_owner")),
) -> DocumentOut:
    doc = session.scalar(
        select(Document).where(
            Document.id == uuid.UUID(document_id),
            Document.household_id == uuid.UUID(user.household_id),
            Document.deleted_at.is_not(None),
        )
    )
    if doc is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not in trash")

    doc.deleted_at = None
    doc.deleted_by = None
    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="restore_document",
            target_table="documents",
            target_id=doc.id,
            household_id=doc.household_id,
        )
    )
    session.commit()
    return DocumentOut.model_validate(doc)


# ---------------------------------------------------------------------------
# Get one — used by iOS to poll parse status
# ---------------------------------------------------------------------------


@router.get("/{document_id}", response_model=DocumentOut)
def get_document(
    document_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
    _module: TokenPayload = Depends(require_module_access("medicalVault", 1)),
) -> DocumentOut:
    """Return a single document. Used by the iOS client to poll parse
    progress (status transitions uploaded → parsing → parsed/failed).
    Caregivers cannot read other users' private documents.
    """
    role = _caller_role(session, user)
    doc = session.scalar(
        select(Document).where(
            Document.id == uuid.UUID(document_id),
            Document.household_id == uuid.UUID(user.household_id),
        )
    )
    if doc is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    _assert_document_readable(doc, role, user)
    return DocumentOut.model_validate(doc)


# ---------------------------------------------------------------------------
# Patch (category, is_private, filename)
# ---------------------------------------------------------------------------


@router.patch("/{document_id}", response_model=DocumentOut)
def patch_document(
    document_id: str,
    body: DocumentPatchIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
    _module: TokenPayload = Depends(require_module_access("medicalVault", 2)),
) -> DocumentOut:
    role = _caller_role(session, user)
    doc = session.scalar(
        select(Document).where(
            Document.id == uuid.UUID(document_id),
            Document.household_id == uuid.UUID(user.household_id),
            Document.deleted_at.is_(None),
        )
    )
    if doc is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    _assert_document_readable(doc, role, user)

    if body.is_private is not None:
        if role == "caregiver":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Caregivers cannot change privacy setting",
            )
        doc.is_private = body.is_private

    if body.category is not None:
        doc.category = body.category
        doc.category_source = "user"

    if body.filename is not None:
        doc.filename = body.filename

    session.commit()
    return DocumentOut.model_validate(doc)


# ---------------------------------------------------------------------------
# Parse
# ---------------------------------------------------------------------------


@router.post("/{document_id}/parse", response_model=ParseResponse)
@limiter.limit("10/minute")
def parse_document(
    request: Request,
    document_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
    _module: TokenPayload = Depends(require_module_access("medicalVault", 2)),
) -> ParseResponse:
    """
    Parse a medical document. Rate-limited (10/min/IP) — each call runs OCR
    plus a paid Claude API request, so this is the endpoint most exposed to
    cost-flooding by a single misbehaving client.

    Steps:
    1. Fetch from storage (S3 or local)
    2. Run OCR
    3. Category-route to Claude (Haiku for admin, Sonnet otherwise)
    4. PHI multi-patient heuristic check
    5. Create suggested tasks
    6. Log family upload notification stub
    """
    doc = session.scalar(
        select(Document).where(
            Document.id == uuid.UUID(document_id),
            Document.household_id == uuid.UUID(user.household_id),
        )
    )
    if doc is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    _assert_document_readable(doc, _caller_role(session, user), user)
    if doc.status not in ("uploaded", "finalized"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Document already parsed or in invalid state",
        )

    try:
        doc.status = "parsing"
        session.commit()

        if not doc.storage_uri:
            raise ValueError("Document has no storage_uri — upload may not have completed")

        storage = get_storage_service()
        file_bytes = storage.get_object_bytes(doc.storage_uri)

        ocr = OCRService()
        ocr_text = ocr.extract_text(file_bytes, doc.mime_type)
        doc.raw_ocr_text = ocr_text

        # Category-routed parse via Grok (grok-4.3 for every category —
        # see services/grok_parser.py for why; swap back to
        # parser_api.services.claude_parser.ClaudeParser to return to
        # Anthropic, its tests and prompts are untouched and still work)
        parser = GrokParser()
        full_summary, simple_summary, suggested_tasks, model_cat = (
            parser.parse_medical_document(ocr_text, category=doc.category)
        )

        # Update category if model provides one and user didn't pin it
        if doc.category_source != "user":
            doc.category = model_cat
            doc.category_source = "model"
        elif model_cat and model_cat != doc.category:
            # User pinned a category, model disagrees — record the suggestion
            doc.category_suggested = model_cat

        # PHI multi-patient detection (feature I)
        flagged, flag_reason = should_flag(ocr_text)
        doc.flagged_for_review = flagged
        doc.flag_reason = flag_reason if flagged else None

        doc.parsed_summary_he = full_summary
        doc.parsed_summary_simple_he = simple_summary
        doc.parsed_at = datetime.now(tz=timezone.utc)
        doc.status = "parsed"
        session.commit()

        for task_data in suggested_tasks:
            task = Task(
                household_id=doc.household_id,
                document_id=doc.id,
                title_he=task_data.title_he,
                original_text=task_data.title_he,
                category=task_data.category,
                status="suggested",
            )
            session.add(task)
        session.commit()

        session.add(
            AuditLog(
                actor_type="parser_api",
                actor_id=user.user_id,
                action="parse",
                target_table="documents",
                target_id=doc.id,
                household_id=doc.household_id,
                metadata_={
                    "task_count": len(suggested_tasks),
                    "category": doc.category,
                    "flagged": flagged,
                },
            )
        )
        session.commit()

        # APNs stub — log notification payload for family members (feature J)
        logger.info("apns_notify_family", extra={
            "event": "document_parsed",
            "household_id": str(doc.household_id),
            "document_id": str(doc.id),
            "uploader_id": user.user_id,
            "category": doc.category,
            "flagged_for_review": flagged,
        })

        # Clean up storage after successful parse
        try:
            storage.delete_object(doc.storage_uri)
            doc.storage_uri = None
            session.commit()
        except Exception:
            pass

        return ParseResponse(
            document_id=uuid.UUID(document_id),
            parsed_summary_he=full_summary,
            parsed_summary_simple_he=simple_summary,
            suggested_tasks=suggested_tasks,
            model_suggested_category=model_cat,
            flagged_for_review=flagged,
        )

    except HTTPException:
        raise
    except Exception as e:
        doc.status = "failed"
        session.commit()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Parsing failed: {str(e)}",
        )
