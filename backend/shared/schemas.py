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
    kind: str = "logistics"
    origin: str = "ai_suggestion"
    due_at: datetime | None
    status: str
    claimed_by: uuid.UUID | None = None
    completed_at: datetime | None = None
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


class TaskCreateIn(BaseModel):
    """Manually created by a family member (mirrors DailyTask) — skips the
    suggested→approve flow since there's no Claude draft to review."""
    title_he: str
    description_he: str | None = None
    kind: str = "logistics"  # medical|logistics
    category: str = "admin"  # appointment|medication|test|admin
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
    parsed_summary_he: str | None
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


class DoseEventOut(_Base):
    id: uuid.UUID
    medication_id: uuid.UUID
    scheduled_at: datetime
    taken_at: datetime | None
    note_he: str | None
    status: str  # upcoming|taken|missed — computed, not stored


class MedicationOut(_Base):
    id: uuid.UUID
    name_he: str
    dosage: str | None
    schedule: dict
    form: str
    usage_instructions: str | None
    stock_count: int
    low_stock_threshold: int


class MedicationIn(BaseModel):
    name_he: str
    dosage: str | None = None
    form: str = "pill"  # pill|injection|syrup|patch
    usage_instructions: str | None = None
    stock_count: int = 0
    low_stock_threshold: int = 5
    dosing_times: list[str] = Field(default_factory=list)  # ["HH:MM", ...]


class MedicationPatchIn(BaseModel):
    name_he: str | None = None
    dosage: str | None = None
    form: str | None = None
    usage_instructions: str | None = None
    stock_count: int | None = None
    low_stock_threshold: int | None = None
    dosing_times: list[str] | None = None


# ---------------------------------------------------------------------------
# Calendar (יומן)
# ---------------------------------------------------------------------------


class ScheduleEventOut(_Base):
    id: uuid.UUID
    title: str
    starts_at: datetime
    kind: str  # medical|routine|logistics
    location_name: str | None
    companion_user_id: uuid.UUID | None
    subtitle: str | None
    created_at: datetime


class ScheduleEventIn(BaseModel):
    title: str
    starts_at: datetime
    kind: str = "routine"
    location_name: str | None = None
    companion_user_id: uuid.UUID | None = None
    subtitle: str | None = None


class ScheduleEventPatchIn(BaseModel):
    title: str | None = None
    starts_at: datetime | None = None
    kind: str | None = None
    location_name: str | None = None
    companion_user_id: uuid.UUID | None = None
    subtitle: str | None = None


# ---------------------------------------------------------------------------
# Feed (פיד)
# ---------------------------------------------------------------------------


class FeedCommentOut(_Base):
    id: uuid.UUID
    author_user_id: uuid.UUID
    body: str
    posted_at: datetime


class FeedCommentIn(BaseModel):
    body: str = Field(..., min_length=1, max_length=2000)


class FeedPostOut(BaseModel):
    id: uuid.UUID
    author_user_id: uuid.UUID
    body: str
    status: str | None
    audience: str
    posted_at: datetime
    heart_count: int = 0
    hug_count: int = 0
    my_reactions: list[str] = Field(default_factory=list)
    comments: list[FeedCommentOut] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class FeedPostIn(BaseModel):
    body: str = Field(..., min_length=1, max_length=4000)
    status: str | None = None  # stable|needs_rest|improving|concerned
    audience: str = "family_only"  # family_only|inner_circle


class FeedReactionIn(BaseModel):
    reaction: str = Field(..., pattern="^(heart|hug)$")


# ---------------------------------------------------------------------------
# Caregiver layer (שכבת מטפל/ת)
# ---------------------------------------------------------------------------


class CaregiverProfileOut(_Base):
    id: uuid.UUID
    display_name: str
    relation_title: str
    preferred_language: str
    is_active: bool
    created_at: datetime


class CaregiverProfileIn(BaseModel):
    display_name: str
    relation_title: str = "מטפל/ת סיעודי/ת"
    preferred_language: str = "english"


class CaregiverProfilePatchIn(BaseModel):
    display_name: str | None = None
    relation_title: str | None = None
    preferred_language: str | None = None
    is_active: bool | None = None


class CaregiverCheckInOut(_Base):
    id: uuid.UUID
    caregiver_id: uuid.UUID
    meal_status: str
    hydration_status: str
    sleep_status: str
    pain_level: int
    nausea_level: int
    fatigue_level: int
    medication_status: str
    medication_note: str | None
    free_text_original: str | None
    original_language: str
    translated_summary_hebrew: str
    attention_level: str
    alert_reasons: list[str]
    is_acknowledged: bool
    created_at: datetime


class CaregiverCheckInIn(BaseModel):
    caregiver_id: uuid.UUID
    meal_status: str
    hydration_status: str
    sleep_status: str
    pain_level: int = Field(ge=0, le=10)
    nausea_level: int = Field(ge=0, le=10)
    fatigue_level: int = Field(ge=0, le=10)
    medication_status: str
    medication_note: str | None = None
    free_text_original: str | None = None
    original_language: str
    # Computed client-side by a deterministic rule-based summarizer
    # (CaregiverTranslationService) — the backend just persists it.
    translated_summary_hebrew: str
    attention_level: str = "ok"
    alert_reasons: list[str] = Field(default_factory=list)


class CaregiverInstructionOut(BaseModel):
    id: uuid.UUID
    kind: str
    detail: str
    created_by_name: str
    is_active: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class CaregiverInstructionIn(BaseModel):
    kind: str
    detail: str = ""


class CaregiverInstructionPatchIn(BaseModel):
    is_active: bool | None = None


# ---------------------------------------------------------------------------
# Household roles
# ---------------------------------------------------------------------------


class HouseholdMemberOut(_Base):
    id: uuid.UUID
    user_id: uuid.UUID
    household_id: uuid.UUID
    role: str
    joined_at: datetime
    display_name: str = ""
    permissions: dict[str, int] | None = None


class MemberPermissionPatchIn(BaseModel):
    module: str = Field(..., pattern="^(schedule|tasks|medications|medicalVault|feed)$")
    level: int = Field(..., ge=0, le=2)


class CoOwnerInviteIn(BaseModel):
    # Optional: when omitted the code is an open one that any signed-in user
    # may redeem. Requiring a user id up front is unusable in practice —
    # the person being invited usually has not signed up yet, so the
    # inviter has no id to name.
    invitee_user_id: uuid.UUID | None = None


class CoOwnerAcceptIn(BaseModel):
    code: str = Field(..., min_length=6, max_length=6)


class CaregiverInviteOut(BaseModel):
    invite_id: uuid.UUID
    code: str  # returned plaintext so inviter can share it
    expires_in_minutes: int


class RedeemInviteIn(BaseModel):
    """Universal join payload. The code alone identifies the household and
    the role — the client never has to know a household UUID, which is what
    makes the code shareable over WhatsApp."""
    code: str = Field(..., min_length=6, max_length=6)


class RedeemInviteOut(BaseModel):
    """Joining moves the user to a different household, and household_id is
    baked into the JWT — so a stale token would keep pointing at the old,
    empty household. A fresh token ships with the response and the client
    swaps it in immediately; without this the join silently does nothing.
    """
    member: HouseholdMemberOut
    access_token: str
    token_type: str = "bearer"
    expires_in_seconds: int


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


class PushTokenIn(BaseModel):
    """APNs device token, registered after the OS grants remote-notification
    permission. `platform` is future-proofing for a possible Android build;
    only "ios" is meaningful today."""
    device_token: str = Field(..., min_length=16, max_length=256)
    platform: str = "ios"


# Apple Sign-In token exchange (POST /v1/auth/apple)


class AppleFullName(BaseModel):
    given_name: str | None = None
    family_name: str | None = None


class AppleAuthIn(BaseModel):
    identity_token: str
    nonce: str  # raw nonce, not hashed; backend hashes for comparison
    full_name: AppleFullName | None = None  # only present on first sign-in


class AppleAuthUserOut(BaseModel):
    id: uuid.UUID
    household_id: uuid.UUID
    role: str  # patient|co_owner|caregiver
    full_name: str


class AppleAuthOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: AppleAuthUserOut
    expires_in_seconds: int


class DevAuthIn(BaseModel):
    """Local-only auth path for testing without Sign In with Apple (which
    requires a paid Apple Developer Program membership even for a
    personal-team device install). The backend refuses this outside
    ENVIRONMENT=development."""
    email: str
    display_name: str | None = None


# Google Sign-In token exchange (POST /v1/auth/google)


class GoogleAuthIn(BaseModel):
    id_token: str
    nonce: str | None = None  # raw nonce; backend hashes for comparison if provided


class GoogleAuthOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: AppleAuthUserOut  # response shape is identical across providers
    expires_in_seconds: int
