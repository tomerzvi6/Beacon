"""initial schema

Revision ID: 001
Revises:
Create Date: 2026-04-28
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    # ------------------------------------------------------------------
    # Track A — PHI tables
    # ------------------------------------------------------------------

    op.create_table(
        "households",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("patient_name_encrypted", sa.LargeBinary, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("apple_user_id", sa.String(128), nullable=False, unique=True),
        sa.Column("display_name", sa.String(120), nullable=False),
        sa.Column("role", sa.String(30), nullable=False),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("push_token", sa.String(256), nullable=True),
        sa.Column("locale", sa.String(10), nullable=False, server_default="he_IL"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index("ix_users_household_id", "users", ["household_id"])

    op.create_table(
        "documents",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("uploaded_by", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("source", sa.String(20), nullable=False),
        sa.Column("storage_uri", sa.Text, nullable=True),
        sa.Column("mime_type", sa.String(80), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="uploaded"),
        sa.Column("parsed_summary_he", sa.Text, nullable=True),
        sa.Column("parsed_summary_simple_he", sa.Text, nullable=True),
        sa.Column("raw_ocr_text", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
        sa.Column("parsed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_documents_household_id", "documents", ["household_id"])

    op.create_table(
        "tasks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("document_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("documents.id"), nullable=True),
        sa.Column("title_he", sa.Text, nullable=False),
        sa.Column("description_he", sa.Text, nullable=True),
        sa.Column("category", sa.String(30), nullable=False),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="suggested"),
        sa.Column("approved_by", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("claimed_by", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=True),
        sa.Column("claimed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index("ix_tasks_household_status", "tasks", ["household_id", "status"])

    op.create_table(
        "medications",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("name_he", sa.Text, nullable=False),
        sa.Column("dosage", sa.String(100), nullable=True),
        sa.Column("schedule", postgresql.JSONB, nullable=False, server_default="{}"),
    )

    op.create_table(
        "dose_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("medication_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("medications.id"), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("taken_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("note_he", sa.Text, nullable=True),
    )
    op.create_index("ix_dose_events_medication_id", "dose_events", ["medication_id"])

    op.create_table(
        "symptom_reports",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("kind", sa.String(50), nullable=False),
        sa.Column("severity", sa.Integer, nullable=True),
        sa.Column("note_he", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )

    op.create_table(
        "audit_log",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column("actor_type", sa.String(40), nullable=False),
        sa.Column("actor_id", sa.String(128), nullable=False),
        sa.Column("action", sa.String(80), nullable=False),
        sa.Column("target_table", sa.String(80), nullable=True),
        sa.Column("target_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("metadata", postgresql.JSONB, nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )

    # ------------------------------------------------------------------
    # Track B — Agent tables (no PHI)
    # ------------------------------------------------------------------

    op.create_table(
        "agent_runs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("agent_name", sa.String(40), nullable=False),
        sa.Column("graph_run_id", sa.String(128), nullable=True),
        sa.Column("status", sa.String(30), nullable=False, server_default="running"),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("input_summary", postgresql.JSONB, nullable=False, server_default="{}"),
        sa.Column("output_draft", postgresql.JSONB, nullable=False, server_default="{}"),
        sa.Column("approver", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("execution_result", postgresql.JSONB, nullable=True),
    )
    op.create_index("ix_agent_runs_status", "agent_runs", ["status"])

    op.create_table(
        "support_tickets",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("channel", sa.String(20), nullable=False),
        sa.Column("subject", sa.Text, nullable=False),
        sa.Column("body", sa.Text, nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="new"),
        sa.Column("draft_response", sa.Text, nullable=True),
        sa.Column("draft_run_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("agent_runs.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )

    op.create_table(
        "agent_metrics_snapshots",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("week_starting", sa.DateTime(timezone=True), nullable=False),
        sa.Column("metrics", postgresql.JSONB, nullable=False, server_default="{}"),
        sa.Column("report_markdown", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )

    op.create_table(
        "doc_chunks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("source", sa.String(256), nullable=False),
        sa.Column("content", sa.Text, nullable=False),
        sa.Column("embedding", sa.Text, nullable=True),  # vector(1536) — raw DDL below
    )
    # pgvector column type requires raw DDL
    op.execute("ALTER TABLE doc_chunks ALTER COLUMN embedding TYPE vector(1536) USING NULL")
    op.execute(
        "CREATE INDEX ix_doc_chunks_embedding ON doc_chunks "
        "USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
    )

    # ------------------------------------------------------------------
    # RLS: enable on PHI tables
    # ------------------------------------------------------------------
    for table in ("users", "documents", "tasks", "medications",
                  "dose_events", "symptom_reports"):
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")

    # household isolation policy for app users
    op.execute("""
        CREATE POLICY household_isolation ON users
            USING (household_id::text = current_setting('app.household_id', true))
    """)
    op.execute("""
        CREATE POLICY household_isolation ON documents
            USING (household_id::text = current_setting('app.household_id', true))
    """)
    op.execute("""
        CREATE POLICY household_isolation ON tasks
            USING (household_id::text = current_setting('app.household_id', true))
    """)
    op.execute("""
        CREATE POLICY household_isolation ON medications
            USING (household_id::text = current_setting('app.household_id', true))
    """)
    op.execute("""
        CREATE POLICY household_isolation ON symptom_reports
            USING (household_id::text = current_setting('app.household_id', true))
    """)

    # dose_events: inherit via medication_id — bypass RLS for parser_api_role (checked at app layer)
    op.execute("""
        CREATE POLICY allow_via_app ON dose_events USING (true)
    """)


def downgrade() -> None:
    for t in (
        "doc_chunks", "agent_metrics_snapshots", "support_tickets", "agent_runs",
        "audit_log", "symptom_reports", "dose_events", "medications",
        "tasks", "documents", "users", "households",
    ):
        op.drop_table(t)
    op.execute("DROP EXTENSION IF EXISTS vector")
    op.execute("DROP EXTENSION IF EXISTS pgcrypto")
