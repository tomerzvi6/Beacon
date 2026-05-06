"""Phase 9.5: Chief Agent tables + embedding column on agent_runs

Revision ID: 005
Revises: 004
Create Date: 2026-05-05
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "005"
down_revision: Union[str, None] = "004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ------------------------------------------------------------------
    # 1. content_embedding on agent_runs (for semantic draft search)
    # ------------------------------------------------------------------
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")
    op.add_column(
        "agent_runs",
        sa.Column("content_embedding", sa.Text, nullable=True),  # stored as text, cast via pgvector
    )
    # We store the embedding as a native vector type; alter after adding
    op.execute("ALTER TABLE agent_runs ADD COLUMN IF NOT EXISTS content_embedding_vec vector(1536)")
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_agent_runs_embedding "
        "ON agent_runs USING hnsw (content_embedding_vec vector_cosine_ops)"
    )

    # ------------------------------------------------------------------
    # 2. initiatives — founder-initiated cross-agent threads
    # ------------------------------------------------------------------
    op.create_table(
        "initiatives",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "target_agent",
            sa.String(30),
            nullable=False,
        ),  # guardian|customer_success|product|creative|cross_agent
        sa.Column("title_he", sa.Text, nullable=False),
        sa.Column("description_he", sa.Text, nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="open"),
        # open|in_progress|waiting_on_agent|completed|cancelled
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("last_check_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("related_draft_ids", postgresql.ARRAY(postgresql.UUID(as_uuid=True)), nullable=True),
    )
    op.create_index("ix_initiatives_status", "initiatives", ["status"])
    op.create_index("ix_initiatives_target_agent", "initiatives", ["target_agent"])

    # ------------------------------------------------------------------
    # 3. chief_briefs — daily synthesised brief with citations
    # ------------------------------------------------------------------
    op.create_table(
        "chief_briefs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("brief_date", sa.Date, nullable=False, unique=True),
        sa.Column("content_he", sa.Text, nullable=False),
        sa.Column("citations", postgresql.JSONB, nullable=False, server_default="[]"),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("model", sa.String(80), nullable=True),
        sa.Column("tokens_used", sa.Integer, nullable=True),
    )
    op.create_index("ix_chief_briefs_date", "chief_briefs", ["brief_date"])

    # ------------------------------------------------------------------
    # 4. chief_conversations — chat history with founder
    # ------------------------------------------------------------------
    op.create_table(
        "chief_conversations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("conversation_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("role", sa.String(10), nullable=False),  # user|chief
        sa.Column("content_he", sa.Text, nullable=False),
        sa.Column("citations", postgresql.JSONB, nullable=True),
        sa.Column("tools_used", postgresql.JSONB, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_chief_conversations_conv_id", "chief_conversations", ["conversation_id"])
    op.create_index("ix_chief_conversations_created_at", "chief_conversations", ["created_at"])

    # ------------------------------------------------------------------
    # 5. pending_agent_tasks — Chief's instructions to operational agents
    # ------------------------------------------------------------------
    op.create_table(
        "pending_agent_tasks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("target_agent", sa.String(30), nullable=False),
        # guardian|customer_success|product|creative
        sa.Column("task_type", sa.String(80), nullable=False),
        sa.Column("description_he", sa.Text, nullable=False),
        sa.Column("payload", postgresql.JSONB, nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        # pending|picked_up|completed|failed
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("requested_by", sa.String(80), nullable=False, server_default="chief_agent"),
        sa.Column("picked_up_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("result_draft_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_index("ix_pending_agent_tasks_target_status", "pending_agent_tasks",
                    ["target_agent", "status"])

    # ------------------------------------------------------------------
    # 6. Permissions — grant SELECT on new tables to agent_role
    # ------------------------------------------------------------------
    for stmt in [
        "GRANT SELECT ON initiatives TO agent_role",
        "GRANT SELECT ON chief_briefs TO agent_role",
        "GRANT SELECT ON chief_conversations TO agent_role",
        "GRANT SELECT, INSERT, UPDATE ON pending_agent_tasks TO agent_role",
        "GRANT INSERT, UPDATE ON initiatives TO agent_role",
        "GRANT INSERT ON chief_briefs TO agent_role",
        "GRANT INSERT ON chief_conversations TO agent_role",
    ]:
        op.execute(stmt)


def downgrade() -> None:
    op.drop_table("pending_agent_tasks")
    op.drop_table("chief_conversations")
    op.drop_table("chief_briefs")
    op.drop_table("initiatives")
    op.execute("DROP INDEX IF EXISTS ix_agent_runs_embedding")
    op.execute("ALTER TABLE agent_runs DROP COLUMN IF EXISTS content_embedding_vec")
    op.drop_column("agent_runs", "content_embedding")
