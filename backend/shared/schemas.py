"""Pydantic v2 schemas — request/response contracts for the Parser API."""
import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class _Base(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------


class SuggestedTask(BaseModel):
    """Shape returned by Claude inside the parse response — not yet persisted as approved."""
    title_he: str
    category: str  # appointment|medication|test|admin
    due_hint: str | None = None  # e.g. "תוך שבוע" — natural language, not a real date


class TaskOut(BaseModel):
    id: uuid.UUID
    title_he: str
    description_he: str | None
    category: str
    due_at: datetime | None
    status: str
    created_at: datetime
    original_text: str | None = None
    edited_by_user: bool = False

    model_config = ConfigDict(from_attributes=True)


class TaskApproveIn(BaseModel):
    pass  # no body needed; user identity comes from JWT


class TaskClaimIn(BaseModel):
    pass


class TaskPatchIn(BaseModel):
    title_he: str | None = None
    description_he: str | None = None
    due_at: datetime | None = None


# ---------------------------------------------------------------------------
# Document upload
# ---------------------------------------------------------------------------

ALLOWED_MIME_TYPES = {
    "application/pdf",
    "image/jpeg",
    "image/png",
    "image/heic",
    "image/heif",
}

DOCUMENT_CATEGORIES = {
    "lab", "prescription", "visit_summary", "referral",
    "imaging", "consult", "admin", "other",
}


class PresignRequest(BaseModel):
    mime_type: str = "application/pdf"
    category: str | None = None
    is_private: bool = False
    filename: str | None = None


class PresignResponse(BaseModel):
    document_id: uuid.UUID
    upload_url: str
    expires_in_seconds: int = 300


class FinalizeDocumentIn(BaseModel):
    document_id: uuid.UUID
    sha256_hex: str = Field(..., min_length=64, max_length=64)
    filename: str | None = None


class FinalizeDocumentOut(BaseModel):
    document_id: uuid.UUID
    status: str  # "ok" | "conflict"
    existing_document_id: uuid.UUID | None = None
    uploaded_at: datetime | None = None
    uploaded_by: uuid.UUID | None = None


class BatchFinalizeIn(BaseModel):
    items: list[FinalizeDocumentIn] = Field(..., min_length=1, max_length=15)
    replace_document_id: uuid.UUID | None = None


class BatchFinalizeOut(BaseModel):
    results: list[FinalizeDocumentOut]


# ---------------------------------------------------------------------------
# Document parsing
# ---------------------------------------------------------------------------


class ParseResponse(BaseModel):
    document_id: uuid.UUID
    parsed_summary_he: str
    parsed_summary_simple_he: str
    suggested_tasks: list[SuggestedTask]
    model_suggested_category: str | None = None
    flagged_for_review: bool = False


# ---------------------------------------------------------------------------
# Document listing / archive
# ---------------------------------------------------------------------------


class DocumentOut(_Base):
    id: uuid.UUID
    household_id: uuid.UUID
    uploaded_by: uuid.UUID
    mime_type: str
    filename: str | None
    status: str
    category: str | None
    category_source: str | None
    category_suggested: str | None
    is_private: bool
    flagged_for_review: bool
    flag_reason: str | None
    parsed_summary_simple_he: str | None
    created_at: datetime
    parsed_at: datetime | None
    deleted_at: datetime | None


class DocumentListParams(BaseModel):
    category: str | None = None
    from_date: datetime | None = None
    to_date: datetime | None = None
    uploaded_by: uuid.UUID | None = None
    q: str | None = None
    include_deleted: bool = False
    limit: int = Field(default=20, ge=1, le=100)
    cursor: str | None = None  # base64-encoded (created_at, id) tuple


class DocumentPatchIn(BaseModel):
    filename: str | None = None
    category: str | None = None
    is_private: bool | None = None  # patient/co_owner only


# ---------------------------------------------------------------------------
# Symptoms & doses
# ---------------------------------------------------------------------------


class SymptomReportIn(BaseModel):
    kind: str  # nausea|fatigue|pain
    severity: int | None = None
    note_he: str | None = None


class SymptomReportOut(_Base):
    id: uuid.UUID
    kind: str
    severity: int | None
    created_at: datetime


class DoseTakenIn(BaseModel):
    note_he: str | None = None


# ---------------------------------------------------------------------------
# Household roles
# ---------------------------------------------------------------------------


class HouseholdMemberOut(_Base):
    id: uuid.UUID
    user_id: uuid.UUID
    household_id: uuid.UUID
    role: str
    joined_at: datetime


class CoOwnerInviteIn(BaseModel):
    invitee_user_id: uuid.UUID


class CoOwnerAcceptIn(BaseModel):
    code: str = Field(..., min_length=6, max_length=6)


class CaregiverInviteOut(BaseModel):
    invite_id: uuid.UUID
    code: str  # returned plaintext so inviter can share it
    expires_in_minutes: int


class CaregiverJoinIn(BaseModel):
    code: str = Field(..., min_length=6, max_length=6)
    household_id: uuid.UUID


# ---------------------------------------------------------------------------
# Agent runs (for Streamlit dashboard reads)
# ---------------------------------------------------------------------------


class AgentRunOut(_Base):
    id: uuid.UUID
    agent_name: str
    status: str
    started_at: datetime
    finished_at: datetime | None
    input_summary: dict
    output_draft: dict
    approved_at: datetime | None


class ApprovalIn(BaseModel):
    edited_draft: dict | None = None  # optional edits before approving


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int = 3600
