"""Document upload presigning."""
import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from parser_api.services.s3_service import S3Service
from shared.models import Document

router = APIRouter(prefix="/v1/uploads", tags=["uploads"])


@router.post("/presign")
def presign_upload(
    mime_type: str = "application/pdf",
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> dict:
    """
    Generate a presigned S3 PUT URL for direct iOS upload.
    Returns document_id (status='uploaded') for later parsing.
    """
    document_id = uuid.uuid4()

    # Create a document record in 'uploaded' state
    doc = Document(
        id=document_id,
        household_id=uuid.UUID(user.household_id),
        uploaded_by=uuid.UUID(user.user_id),
        source="upload",
        mime_type=mime_type,
        status="uploaded",
    )
    session.add(doc)
    session.commit()

    # Generate presigned URL
    s3 = S3Service()
    upload_url = s3.generate_presigned_url(str(document_id), mime_type)

    return {
        "document_id": str(document_id),
        "upload_url": upload_url,
        "expires_in_seconds": 300,
    }
