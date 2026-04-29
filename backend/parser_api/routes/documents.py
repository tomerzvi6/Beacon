"""Medical document parsing pipeline."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from parser_api.services.claude_parser import ClaudeParser
from parser_api.services.ocr_service import OCRService
from parser_api.services.s3_service import S3Service
from shared.models import AuditLog, Document, Task
from shared.schemas import ParseResponse

router = APIRouter(prefix="/v1/documents", tags=["documents"])


@router.post("/{document_id}/parse", response_model=ParseResponse)
def parse_document(
    document_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> ParseResponse:
    """
    Parse a medical document:
    1. Fetch from S3
    2. Run OCR (Textract/Tesseract)
    3. Call Claude Sonnet 4.6 for structured extraction
    4. Create suggested tasks (status='suggested', awaiting user approval)
    5. Delete raw doc from S3 (lifecycle policy)
    """

    # Fetch document record
    doc = session.query(Document).filter(Document.id == document_id).first()
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")

    if doc.status != "uploaded":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Document already parsed or in invalid state",
        )

    try:
        # Mark as parsing
        doc.status = "parsing"
        session.commit()

        # Download from S3 using the URI recorded at upload time
        if not doc.storage_uri:
            raise ValueError("Document has no storage_uri — upload may not have completed")
        s3 = S3Service()
        file_bytes = s3.get_object_bytes(doc.storage_uri)

        # OCR
        ocr = OCRService()
        ocr_text = ocr.extract_text(file_bytes, doc.mime_type)

        # Store raw OCR for audit/debug
        doc.raw_ocr_text = ocr_text

        # Parse with Claude
        parser = ClaudeParser()
        full_summary, simple_summary, suggested_tasks = parser.parse_medical_document(ocr_text)

        # Persist summaries
        doc.parsed_summary_he = full_summary
        doc.parsed_summary_simple_he = simple_summary
        doc.parsed_at = datetime.now(tz=timezone.utc)
        doc.status = "parsed"
        session.commit()

        # Create suggested task records (NOT approved yet — user must click "Approve")
        for task_data in suggested_tasks:
            task = Task(
                household_id=doc.household_id,
                document_id=doc.id,
                title_he=task_data.title_he,
                category=task_data.category,
                status="suggested",  # Awaiting user approval
            )
            session.add(task)

        session.commit()

        # Audit log
        session.add(
            AuditLog(
                actor_type="parser_api",
                actor_id=user.user_id,
                action="parse",
                target_table="documents",
                target_id=doc.id,
                household_id=doc.household_id,
                metadata_={"task_count": len(suggested_tasks)},
            )
        )
        session.commit()

        # Delete raw document from S3 then null out storage_uri
        try:
            s3.delete_object(doc.storage_uri)
            doc.storage_uri = None
            session.commit()
        except Exception:
            pass  # Don't fail parsing if cleanup fails

        return ParseResponse(
            document_id=document_id,
            parsed_summary_he=full_summary,
            parsed_summary_simple_he=simple_summary,
            suggested_tasks=suggested_tasks,
        )

    except Exception as e:
        doc.status = "failed"
        session.commit()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Parsing failed: {str(e)}",
        )
