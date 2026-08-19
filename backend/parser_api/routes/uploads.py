"""Document upload: presign, finalize, batch, and local-dev PUT handler."""
import hashlib
import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from parser_api.middleware import limiter
from parser_api.services.storage_service import get_storage_service
from shared.models import AuditLog, Document
from shared.schemas import (
    ALLOWED_MIME_TYPES,
    BatchFinalizeIn,
    BatchFinalizeOut,
    FinalizeDocumentIn,
    FinalizeDocumentOut,
    PresignRequest,
    PresignResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/uploads", tags=["uploads"])


# ---------------------------------------------------------------------------
# Presign
# ---------------------------------------------------------------------------


@router.post("/presign", response_model=PresignResponse)
@limiter.limit("20/minute")
def presign_upload(
    request: Request,
    body: PresignRequest,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> PresignResponse:
    """
    Generate a presigned PUT URL for direct iOS upload.
    Creates a Document record in 'uploaded' state; client finalizes after PUT.
    Rate-limited (20/min/IP) to bound Document-row / storage churn from a
    single misbehaving client.
    """
    if body.mime_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported mime type '{body.mime_type}'. "
                   f"Allowed: {sorted(ALLOWED_MIME_TYPES)}",
        )

    document_id = uuid.uuid4()
    storage = get_storage_service()
    storage_uri = storage.storage_uri_for(str(document_id))

    doc = Document(
        id=document_id,
        household_id=uuid.UUID(user.household_id),
        uploaded_by=uuid.UUID(user.user_id),
        source="upload",
        storage_uri=storage_uri,
        mime_type=body.mime_type,
        filename=body.filename,
        status="uploaded",
        category=body.category,
        category_source="user" if body.category else None,
        is_private=body.is_private,
    )
    session.add(doc)
    session.commit()

    upload_url = storage.generate_presigned_url(str(document_id), body.mime_type)
    return PresignResponse(
        document_id=document_id,
        upload_url=upload_url,
        expires_in_seconds=300,
    )


# ---------------------------------------------------------------------------
# Finalize (single)
# ---------------------------------------------------------------------------


def _finalize_one(
    item: FinalizeDocumentIn,
    session: Session,
    user_id: str,
    household_id: str,
) -> FinalizeDocumentOut:
    doc = session.scalar(
        select(Document).where(
            Document.id == item.document_id,
            Document.household_id == uuid.UUID(household_id),
        )
    )
    if doc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Document {item.document_id} not found",
        )
    if doc.status != "uploaded":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Document {item.document_id} already finalized",
        )

    # Deduplication: check (household_id, content_hash) — partial index enforces uniqueness
    existing = session.scalar(
        select(Document).where(
            Document.household_id == uuid.UUID(household_id),
            Document.content_hash == item.sha256_hex,
            Document.deleted_at.is_(None),
            Document.id != item.document_id,
        )
    )
    if existing:
        # Discard the redundant upload
        storage = get_storage_service()
        try:
            storage.delete_object(doc.storage_uri)
        except Exception:
            pass
        doc.deleted_at = datetime.now(tz=timezone.utc)
        doc.deleted_by = uuid.UUID(user_id)
        session.commit()
        return FinalizeDocumentOut(
            document_id=item.document_id,
            status="conflict",
            existing_document_id=existing.id,
            uploaded_at=existing.created_at,
            uploaded_by=existing.uploaded_by,
        )

    doc.content_hash = item.sha256_hex
    if item.filename:
        doc.filename = item.filename
    doc.status = "finalized"
    session.commit()

    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user_id,
            action="finalize_upload",
            target_table="documents",
            target_id=doc.id,
            household_id=doc.household_id,
        )
    )
    session.commit()

    return FinalizeDocumentOut(
        document_id=doc.id,
        status="ok",
        uploaded_at=doc.created_at,
        uploaded_by=doc.uploaded_by,
    )


@router.post("/finalize", response_model=FinalizeDocumentOut, status_code=status.HTTP_200_OK)
def finalize_upload(
    body: FinalizeDocumentIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> FinalizeDocumentOut:
    return _finalize_one(body, session, user.user_id, user.household_id)


# ---------------------------------------------------------------------------
# Batch finalize (up to 15)
# ---------------------------------------------------------------------------


@router.post("/finalize/batch", response_model=BatchFinalizeOut)
def finalize_batch(
    body: BatchFinalizeIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> BatchFinalizeOut:
    results = [
        _finalize_one(item, session, user.user_id, user.household_id)
        for item in body.items
    ]
    return BatchFinalizeOut(results=results)


# ---------------------------------------------------------------------------
# Local-dev PUT handler
# ---------------------------------------------------------------------------


MAX_UPLOAD_BYTES = 26_214_400  # 25 MB — matches StorageService.generate_presigned_url default


@router.put("/local/{document_id}", include_in_schema=False)
@limiter.limit("20/minute")
async def local_upload(
    document_id: str,
    request: Request,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> dict:
    """
    Receives raw bytes PUT by the iOS client. Despite the name this is the
    real production upload path whenever STORAGE_BACKEND=local (no S3
    configured) — it is NOT dev-only, so it needs the same auth and
    ownership checks as every other document-touching route: the caller
    must hold a valid JWT for the household that owns the document (i.e.
    they called POST /presign first), and the document must still be
    'uploaded' (not already finalized). Size is capped and streamed to a
    temp file so we never buffer more than MAX_UPLOAD_BYTES in memory and
    never leave a truncated file at the final path.
    """
    from parser_api.services.storage_service import LocalDiskStorageService, get_storage_service

    storage = get_storage_service()
    if not isinstance(storage, LocalDiskStorageService):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Local upload endpoint only available in local storage mode",
        )

    try:
        doc_uuid = uuid.UUID(document_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")

    doc = session.scalar(
        select(Document).where(
            Document.id == doc_uuid,
            Document.household_id == uuid.UUID(user.household_id),
        )
    )
    if doc is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    if doc.status != "uploaded":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Document {document_id} already finalized",
        )

    dest = storage.path_for(document_id)
    tmp_path = dest.with_name(dest.name + ".part")
    total = 0
    try:
        with tmp_path.open("wb") as f:
            async for chunk in request.stream():
                total += len(chunk)
                if total > MAX_UPLOAD_BYTES:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail=f"Upload exceeds {MAX_UPLOAD_BYTES} byte limit",
                    )
                f.write(chunk)
        if total == 0:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty body")
        tmp_path.replace(dest)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise

    logger.info("local_upload stored", extra={"document_id": document_id, "bytes": total})
    return {"status": "ok", "document_id": document_id, "bytes": total}
