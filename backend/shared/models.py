"""SQLAlchemy 2.0 ORM models — both Track A (PHI) and Track B (agents)."""
import uuid
from datetime import datetime
from typing import Optional

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    ARRAY,
    BigInteger,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from shared.db import Base


def _uuid() -> uuid.UUID:
    return uuid.uuid4()


def _now() -> datetime:
    return datetime.utcnow()


# ---------------------------------------------------------------------------
# Track A — PHI tables (owned by parser_api_role)
# ---------------------------------------------------------------------------


class Household(Base):
    __tablename__ = "households"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    patient_name_encrypted: Mapped[bytes | None] = mapped_column(LargeBinary)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    users: Mapped[list["User"]] = relationship(back_populates="household")
    members: Mapped[list["HouseholdMember"]] = relationship(back_populates="household")
    documents: Mapped[list["Document"]] = relationship(back_populates="household")
    tasks: Mapped[list["Task"]] = relationship(back_populates="household")
    medications: Mapped[list["Medication"]] = relationship(back_populates="household")
    symptom_reports: Mapped[list["SymptomReport"]] = relationship(back_populates="household")
    schedule_events: Mapped[list["ScheduleEvent"]] = relationship(back_populates="household")
    feed_posts: Mapped[list["FeedPost"]] = relationship(back_populates="household")
    caregiver_profiles: Mapped[list["CaregiverProfile"]] = relationship(back_populates="household")


class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("apple_user_id"),
        UniqueConstraint("google_user_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    # Exactly one of apple_user_id / google_user_id is set per user (Phase 9.1.5).
    apple_user_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    google_user_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    display_name: Mapped[str] = mapped_column(String(120))
    # legacy role column — authoritative membership is in household_members
    role: Mapped[str] = mapped_column(String(30))
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    push_token: Mapped[str | None] = mapped_column(String(256))
    locale: Mapped[str] = mapped_column(String(10), default="he_IL")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    household: Mapped[Household] = relationship(back_populates="users")
    memberships: Mapped[list["HouseholdMember"]] = relationship(
        back_populates="user",
        foreign_keys="HouseholdMember.user_id",
    )


class HouseholdMember(Base):
    """
    Authoritative membership table.  Replaces users.role for permission checks.
    Partial unique indexes (in migration) enforce one patient + one co_owner per household.
    """
    __tablename__ = "household_members"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    role: Mapped[str] = mapped_column(String(20), nullable=False)  # patient|co_owner|caregiver
    invited_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id"), nullable=True
    )
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    household: Mapped[Household] = relationship(back_populates="members")
    user: Mapped[User] = relationship(back_populates="memberships", foreign_keys=[user_id])


class HouseholdInvite(Base):
    """6-digit invite code for co_owner (sent to specific user) or caregiver (open)."""
    __tablename__ = "household_invites"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"), nullable=False)
    # None for open caregiver invites; set for targeted co_owner invites
    invitee_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id"), nullable=True
    )
    role: Mapped[str] = mapped_column(String(20), nullable=False)  # co_owner|caregiver
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)  # SHA-256 of 6-digit code
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class Document(Base):
    __tablename__ = "documents"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    uploaded_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    source: Mapped[str] = mapped_column(String(20))  # upload|hospital_sync
    storage_uri: Mapped[str | None] = mapped_column(Text)  # nulled after successful parse
    mime_type: Mapped[str] = mapped_column(String(80))
    filename: Mapped[str | None] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(20), default="uploaded")

    # Categorization
    # lab|prescription|visit_summary|referral|imaging|consult|admin|other
    category: Mapped[str | None] = mapped_column(String(30))
    category_source: Mapped[str | None] = mapped_column(String(10))   # user|model
    category_suggested: Mapped[str | None] = mapped_column(String(30))  # model's disagreement

    # Parsing output
    parsed_summary_he: Mapped[str | None] = mapped_column(Text)
    parsed_summary_simple_he: Mapped[str | None] = mapped_column(Text)
    raw_ocr_text: Mapped[str | None] = mapped_column(Text)  # encrypted via pgcrypto at rest
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    parsed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Deduplication
    content_hash: Mapped[str | None] = mapped_column(String(64))  # SHA-256 hex

    # Privacy
    is_private: Mapped[bool] = mapped_column(Boolean, default=False)

    # Soft delete
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id"), nullable=True
    )

    # PHI multi-patient flag
    flagged_for_review: Mapped[bool] = mapped_column(Boolean, default=False)
    flag_reason: Mapped[str | None] = mapped_column(Text)

    household: Mapped[Household] = relationship(back_populates="documents")
    tasks: Mapped[list["Task"]] = relationship(back_populates="document")


class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    document_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("documents.id"))
    title_he: Mapped[str] = mapped_column(Text)
    description_he: Mapped[str | None] = mapped_column(Text)
    category: Mapped[str] = mapped_column(String(30))  # appointment|medication|test|admin
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(20), default="suggested")
    approved_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    claimed_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    # Audit trail
    original_text: Mapped[str | None] = mapped_column(Text)  # set once from Claude, never overwritten
    edited_by_user: Mapped[bool] = mapped_column(Boolean, default=False)
    edit_history: Mapped[list] = mapped_column(JSONB, default=list)

    # DailyTask parity (Phase 9.6)
    kind: Mapped[str] = mapped_column(String(20), default="logistics")  # medical|logistics
    origin: Mapped[str] = mapped_column(String(20), default="ai_suggestion")
    # manual|ai_suggestion|hospital_sync

    household: Mapped[Household] = relationship(back_populates="tasks")
    document: Mapped[Document | None] = relationship(back_populates="tasks")


class Medication(Base):
    __tablename__ = "medications"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    name_he: Mapped[str] = mapped_column(Text)
    dosage: Mapped[str | None] = mapped_column(String(100))
    schedule: Mapped[dict] = mapped_column(JSONB, default=dict)

    # Medication/MedicationDose parity (Phase 9.6)
    form: Mapped[str] = mapped_column(String(20), default="pill")  # pill|injection|syrup|patch
    usage_instructions: Mapped[str | None] = mapped_column(Text)
    stock_count: Mapped[int] = mapped_column(Integer, default=0)
    low_stock_threshold: Mapped[int] = mapped_column(Integer, default=5)

    household: Mapped[Household] = relationship(back_populates="medications")
    dose_events: Mapped[list["DoseEvent"]] = relationship(back_populates="medication")


class DoseEvent(Base):
    __tablename__ = "dose_events"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    medication_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("medications.id"))
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    taken_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    note_he: Mapped[str | None] = mapped_column(Text)

    medication: Mapped[Medication] = relationship(back_populates="dose_events")


class SymptomReport(Base):
    __tablename__ = "symptom_reports"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    kind: Mapped[str] = mapped_column(String(50))  # nausea|fatigue|pain
    severity: Mapped[int | None] = mapped_column(Integer)
    note_he: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    household: Mapped[Household] = relationship(back_populates="symptom_reports")


class ScheduleEvent(Base):
    """Calendar (יומן): appointments and other scheduled events."""
    __tablename__ = "schedule_events"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    title: Mapped[str] = mapped_column(Text)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    kind: Mapped[str] = mapped_column(String(20), default="routine")  # medical|routine|logistics
    location_name: Mapped[str | None] = mapped_column(Text)
    companion_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    subtitle: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    household: Mapped[Household] = relationship(back_populates="schedule_events")


class FeedPost(Base):
    """Family support feed (פיד)."""
    __tablename__ = "feed_posts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    author_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(Text)
    status: Mapped[str | None] = mapped_column(String(20))  # stable|needs_rest|improving|concerned
    audience: Mapped[str] = mapped_column(String(20), default="family_only")  # family_only|inner_circle
    posted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    household: Mapped[Household] = relationship(back_populates="feed_posts")
    comments: Mapped[list["FeedComment"]] = relationship(
        back_populates="post", cascade="all, delete-orphan", order_by="FeedComment.posted_at"
    )
    reactions: Mapped[list["FeedReaction"]] = relationship(
        back_populates="post", cascade="all, delete-orphan"
    )


class FeedComment(Base):
    __tablename__ = "feed_comments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    post_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("feed_posts.id", ondelete="CASCADE"))
    author_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(Text)
    posted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    post: Mapped[FeedPost] = relationship(back_populates="comments")


class FeedReaction(Base):
    """One row per (post, user, reaction) — idempotent heart/hug taps."""
    __tablename__ = "feed_reactions"
    __table_args__ = (UniqueConstraint("post_id", "user_id", "reaction"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    post_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("feed_posts.id", ondelete="CASCADE"))
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    reaction: Mapped[str] = mapped_column(String(10))  # heart|hug
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    post: Mapped[FeedPost] = relationship(back_populates="reactions")


class CaregiverProfile(Base):
    """A home caregiver/aide (שכבת מטפל/ת). No login — the family maintains
    this record and the caregiver reports through a code-free screen."""
    __tablename__ = "caregiver_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    display_name: Mapped[str] = mapped_column(String(120))
    relation_title: Mapped[str] = mapped_column(String(120), default="מטפל/ת סיעודי/ת")
    preferred_language: Mapped[str] = mapped_column(String(20), default="english")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    household: Mapped[Household] = relationship(back_populates="caregiver_profiles")
    checkins: Mapped[list["CaregiverCheckIn"]] = relationship(back_populates="caregiver")


class CaregiverCheckIn(Base):
    __tablename__ = "caregiver_checkins"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    caregiver_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("caregiver_profiles.id"))

    meal_status: Mapped[str] = mapped_column(String(20))  # ateWell|ateLittle|didNotEat
    hydration_status: Mapped[str] = mapped_column(String(20))  # drankEnough|drankLittle|didNotDrink
    sleep_status: Mapped[str] = mapped_column(String(20))  # sleptWell|sleptPoorly
    pain_level: Mapped[int] = mapped_column(Integer)
    nausea_level: Mapped[int] = mapped_column(Integer)
    fatigue_level: Mapped[int] = mapped_column(Integer)
    medication_status: Mapped[str] = mapped_column(String(20))  # taken|missed|notSure
    medication_note: Mapped[str | None] = mapped_column(Text)

    free_text_original: Mapped[str | None] = mapped_column(Text)
    original_language: Mapped[str] = mapped_column(String(20))
    translated_summary_hebrew: Mapped[str] = mapped_column(Text)

    attention_level: Mapped[str] = mapped_column(String(20), default="ok")  # ok|attention|urgent
    alert_reasons: Mapped[list] = mapped_column(JSONB, default=list)
    is_acknowledged: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    caregiver: Mapped[CaregiverProfile] = relationship(back_populates="checkins")


class CaregiverInstruction(Base):
    __tablename__ = "caregiver_instructions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    kind: Mapped[str] = mapped_column(String(30))
    detail: Mapped[str] = mapped_column(Text, default="")
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class AuditLog(Base):
    __tablename__ = "audit_log"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    actor_type: Mapped[str] = mapped_column(String(40))
    actor_id: Mapped[str] = mapped_column(String(128))
    action: Mapped[str] = mapped_column(String(80))
    target_table: Mapped[str | None] = mapped_column(String(80))
    target_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    household_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    metadata_: Mapped[dict] = mapped_column("metadata", JSONB, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


# ---------------------------------------------------------------------------
# Track B — Agent tables (no PHI; owned by agents service)
# ---------------------------------------------------------------------------


class AgentRun(Base):
    __tablename__ = "agent_runs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    agent_name: Mapped[str] = mapped_column(String(40))
    graph_run_id: Mapped[str | None] = mapped_column(String(128))
    status: Mapped[str] = mapped_column(String(30), default="running")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    input_summary: Mapped[dict] = mapped_column(JSONB, default=dict)
    output_draft: Mapped[dict] = mapped_column(JSONB, default=dict)
    approver: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    execution_result: Mapped[dict | None] = mapped_column(JSONB)


class SupportTicket(Base):
    __tablename__ = "support_tickets"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    channel: Mapped[str] = mapped_column(String(20))  # email|in_app
    subject: Mapped[str] = mapped_column(Text)
    body: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="new")
    draft_response: Mapped[str | None] = mapped_column(Text)
    draft_run_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("agent_runs.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class AgentMetricsSnapshot(Base):
    __tablename__ = "agent_metrics_snapshots"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    week_starting: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    metrics: Mapped[dict] = mapped_column(JSONB, default=dict)
    report_markdown: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class DocChunk(Base):
    """RAG corpus for the Support agent — public app docs only, NO PHI."""
    __tablename__ = "doc_chunks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    source: Mapped[str] = mapped_column(String(256))
    content: Mapped[str] = mapped_column(Text)
    embedding: Mapped[list[float]] = mapped_column(Vector(1536))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


# ---------------------------------------------------------------------------
# Track B — Chief Agent tables (no PHI; Phase 9.5)
# ---------------------------------------------------------------------------


class Initiative(Base):
    """Founder-initiated cross-agent threads tracked by the Chief Agent."""
    __tablename__ = "initiatives"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    target_agent: Mapped[str] = mapped_column(String(30), nullable=False)
    title_he: Mapped[str] = mapped_column(Text, nullable=False)
    description_he: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="open")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    last_check_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    related_draft_ids: Mapped[list | None] = mapped_column(JSONB, nullable=True)


class ChiefBrief(Base):
    """Daily synthesised brief with citations from all 4 agents."""
    __tablename__ = "chief_briefs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    brief_date: Mapped[datetime] = mapped_column(Date, nullable=False, unique=True)
    content_he: Mapped[str] = mapped_column(Text, nullable=False)
    citations: Mapped[list] = mapped_column(JSONB, default=list)
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    model: Mapped[str | None] = mapped_column(String(80), nullable=True)
    tokens_used: Mapped[int | None] = mapped_column(Integer, nullable=True)


class ChiefConversation(Base):
    """Chat message in a Chief Agent ↔ founder conversation."""
    __tablename__ = "chief_conversations"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    conversation_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    role: Mapped[str] = mapped_column(String(10), nullable=False)  # user|chief
    content_he: Mapped[str] = mapped_column(Text, nullable=False)
    citations: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    tools_used: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class PendingAgentTask(Base):
    """Chief Agent's instructions queued for operational agents to pick up."""
    __tablename__ = "pending_agent_tasks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    target_agent: Mapped[str] = mapped_column(String(30), nullable=False)
    task_type: Mapped[str] = mapped_column(String(80), nullable=False)
    description_he: Mapped[str] = mapped_column(Text, nullable=False)
    payload: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    requested_by: Mapped[str] = mapped_column(String(80), default="chief_agent")
    picked_up_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    result_draft_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
