"""Pydantic v2 schemas — request/response contracts for the Parser API."""
import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


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

    model_config = ConfigDict(from_attributes=True)


class TaskApproveIn(BaseModel):
    pass  # no body needed; user identity comes from JWT


class TaskClaimIn(BaseModel):
    pass


# ---------------------------------------------------------------------------
# Document parsing
# ---------------------------------------------------------------------------


class PresignResponse(BaseModel):
    document_id: uuid.UUID
    upload_url: str  # presigned S3 PUT URL
    expires_in_seconds: int = 300


class ParseResponse(BaseModel):
    document_id: uuid.UUID
    parsed_summary_he: str
    parsed_summary_simple_he: str
    suggested_tasks: list[SuggestedTask]


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
