"""Phase 8: household roles, document categorization, dedup, soft-delete, task audit trail

Revision ID: 002
Revises: 001
Create Date: 2026-04-29
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ------------------------------------------------------------------
    # A. household_members — authoritative role table
    # ------------------------------------------------------------------
    op.create_table(
        "household_members",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("role", sa.String(20), nullable=False),  # patient|co_owner|caregiver
        sa.Column("invited_by", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=True),
        sa.Column("joined_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index("ix_household_members_household_id", "household_members", ["household_id"])
    op.create_index("ix_household_members_user_id", "household_members", ["user_id"])

    # One patient per household
    op.execute("""
        CREATE UNIQUE INDEX uq_household_one_patient
        ON household_members (household_id)
        WHERE role = 'patient'
    """)
    # One co_owner per household
    op.execute("""
        CREATE UNIQUE INDEX uq_household_one_coowner
        ON household_members (household_id)
        WHERE role = 'co_owner'
    """)
    # No duplicate memberships
    op.create_index(
        "uq_household_members_user_household",
        "household_members", ["household_id", "user_id"], unique=True,
    )

    # ------------------------------------------------------------------
    # A. household_invites — 6-digit code invitations
    # ------------------------------------------------------------------
    op.create_table(
        "household_invites",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("invitee_user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=True),
        sa.Column("role", sa.String(20), nullable=False),  # co_owner|caregiver
        sa.Column("code_hash", sa.String(64), nullable=False),  # SHA-256 of 6-digit code
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_by", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )

    # ------------------------------------------------------------------
    # B/C/D/E/H/I. documents — new columns
    # ------------------------------------------------------------------
    op.add_column("documents", sa.Column("filename", sa.String(255), nullable=True))
    op.add_column("documents", sa.Column("category", sa.String(30), nullable=True))
    op.add_column("documents", sa.Column("category_source", sa.String(10), nullable=True))
    op.add_column("documents", sa.Column("category_suggested", sa.String(30), nullable=True))
    op.add_column("documents", sa.Column("content_hash", sa.String(64), nullable=True))
    op.add_column("documents", sa.Column(
        "is_private", sa.Boolean, nullable=False, server_default="false"
    ))
    op.add_column("documents", sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("documents", sa.Column(
        "deleted_by", postgresql.UUID(as_uuid=True),
        sa.ForeignKey("users.id"), nullable=True
    ))
    op.add_column("documents", sa.Column(
        "flagged_for_review", sa.Boolean, nullable=False, server_default="false"
    ))
    op.add_column("documents", sa.Column("flag_reason", sa.Text, nullable=True))

    # Dedup: unique (household_id, content_hash) WHERE deleted_at IS NULL
    op.execute("""
        CREATE UNIQUE INDEX uq_documents_household_hash
        ON documents (household_id, content_hash)
        WHERE deleted_at IS NULL AND content_hash IS NOT NULL
    """)

    # FTS: GIN index on parsed summaries + filename for `q` search
    op.execute("""
        CREATE INDEX ix_documents_fts ON documents
        USING gin(
            to_tsvector('simple',
                COALESCE(parsed_summary_he, '') || ' ' ||
                COALESCE(parsed_summary_simple_he, '') || ' ' ||
                COALESCE(filename, '')
            )
        )
    """)

    # ------------------------------------------------------------------
    # G. tasks — audit trail columns
    # ------------------------------------------------------------------
    op.add_column("tasks", sa.Column("original_text", sa.Text, nullable=True))
    op.add_column("tasks", sa.Column(
        "edited_by_user", sa.Boolean, nullable=False, server_default="false"
    ))
    op.add_column("tasks", sa.Column(
        "edit_history", postgresql.JSONB, nullable=False, server_default="[]"
    ))

    # ------------------------------------------------------------------
    # A. Backfill household_members from existing users (seed compat)
    # Each existing user becomes a 'patient' of their household.
    # ------------------------------------------------------------------
    op.execute("""
        INSERT INTO household_members (id, household_id, user_id, role, joined_at, created_at)
        SELECT gen_random_uuid(), household_id, id, 'patient', created_at, created_at
        FROM users
        ON CONFLICT DO NOTHING
    """)

    # ------------------------------------------------------------------
    # Grants for new tables
    # ------------------------------------------------------------------
    for stmt in [
        "GRANT SELECT, INSERT, UPDATE, DELETE ON household_members TO parser_api_role",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON household_invites TO parser_api_role",
        "GRANT SELECT ON household_members TO agent_role",
    ]:
        op.execute(stmt)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_household_one_patient")
    op.execute("DROP INDEX IF EXISTS uq_household_one_coowner")
    op.execute("DROP INDEX IF EXISTS uq_documents_household_hash")
    op.execute("DROP INDEX IF EXISTS ix_documents_fts")

    for col in ("original_text", "edited_by_user", "edit_history"):
        op.drop_column("tasks", col)

    for col in ("filename", "category", "category_source", "category_suggested",
                "content_hash", "is_private", "deleted_at", "deleted_by",
                "flagged_for_review", "flag_reason"):
        op.drop_column("documents", col)

    op.drop_table("household_invites")
    op.drop_table("household_members")
