"""Calendar, feed, and caregiver-layer schema; missing fields on tasks/medications

Revision ID: 006
Revises: 005
Create Date: 2026-08-18
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "006"
down_revision: Union[str, None] = "005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ------------------------------------------------------------------
    # A. schedule_events — calendar (יומן)
    # ------------------------------------------------------------------
    op.create_table(
        "schedule_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("title", sa.Text, nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False, server_default="routine"),
        # medical|routine|logistics
        sa.Column("location_name", sa.Text, nullable=True),
        sa.Column("companion_user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=True),
        sa.Column("subtitle", sa.Text, nullable=True),
        sa.Column("created_by", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index("ix_schedule_events_household_starts", "schedule_events",
                     ["household_id", "starts_at"])

    # ------------------------------------------------------------------
    # B. feed_posts / feed_comments / feed_reactions (פיד)
    # ------------------------------------------------------------------
    op.create_table(
        "feed_posts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("author_user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("body", sa.Text, nullable=False),
        sa.Column("status", sa.String(20), nullable=True),
        # stable|needs_rest|improving|concerned
        sa.Column("audience", sa.String(20), nullable=False, server_default="family_only"),
        # family_only|inner_circle
        sa.Column("posted_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index("ix_feed_posts_household_posted", "feed_posts",
                     ["household_id", "posted_at"])

    op.create_table(
        "feed_comments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("post_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("author_user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("body", sa.Text, nullable=False),
        sa.Column("posted_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index("ix_feed_comments_post_id", "feed_comments", ["post_id"])

    op.create_table(
        "feed_reactions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("post_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("reaction", sa.String(10), nullable=False),  # heart|hug
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index(
        "uq_feed_reactions_post_user_reaction", "feed_reactions",
        ["post_id", "user_id", "reaction"], unique=True,
    )

    # ------------------------------------------------------------------
    # C. caregiver_profiles / caregiver_checkins / caregiver_instructions
    #    (שכבת מטפל/ת — home aide has no login; family manages the record)
    # ------------------------------------------------------------------
    op.create_table(
        "caregiver_profiles",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("display_name", sa.String(120), nullable=False),
        sa.Column("relation_title", sa.String(120), nullable=False,
                  server_default="מטפל/ת סיעודי/ת"),
        sa.Column("preferred_language", sa.String(20), nullable=False, server_default="english"),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("created_by", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index("ix_caregiver_profiles_household_id", "caregiver_profiles", ["household_id"])

    op.create_table(
        "caregiver_checkins",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("caregiver_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("caregiver_profiles.id"), nullable=False),
        sa.Column("meal_status", sa.String(20), nullable=False),
        sa.Column("hydration_status", sa.String(20), nullable=False),
        sa.Column("sleep_status", sa.String(20), nullable=False),
        sa.Column("pain_level", sa.Integer, nullable=False),
        sa.Column("nausea_level", sa.Integer, nullable=False),
        sa.Column("fatigue_level", sa.Integer, nullable=False),
        sa.Column("medication_status", sa.String(20), nullable=False),
        sa.Column("medication_note", sa.Text, nullable=True),
        sa.Column("free_text_original", sa.Text, nullable=True),
        sa.Column("original_language", sa.String(20), nullable=False),
        sa.Column("translated_summary_hebrew", sa.Text, nullable=False),
        sa.Column("attention_level", sa.String(20), nullable=False, server_default="ok"),
        # ok|attention|urgent
        sa.Column("alert_reasons", postgresql.JSONB, nullable=False, server_default="[]"),
        sa.Column("is_acknowledged", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index("ix_caregiver_checkins_household_created", "caregiver_checkins",
                     ["household_id", "created_at"])

    op.create_table(
        "caregiver_instructions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("household_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("households.id"), nullable=False),
        sa.Column("kind", sa.String(30), nullable=False),
        sa.Column("detail", sa.Text, nullable=False, server_default=""),
        sa.Column("created_by", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index("ix_caregiver_instructions_household_id", "caregiver_instructions",
                     ["household_id"])

    # ------------------------------------------------------------------
    # D. tasks — kind + origin (DailyTask parity)
    # ------------------------------------------------------------------
    op.add_column("tasks", sa.Column("kind", sa.String(20), nullable=True))
    op.add_column("tasks", sa.Column(
        "origin", sa.String(20), nullable=False, server_default="ai_suggestion"
    ))
    # Backfill kind from the existing (finer-grained) category taxonomy.
    op.execute("""
        UPDATE tasks SET kind = CASE
            WHEN category IN ('appointment', 'medication', 'test') THEN 'medical'
            ELSE 'logistics'
        END
        WHERE kind IS NULL
    """)
    op.alter_column("tasks", "kind", nullable=False, server_default="logistics")

    # ------------------------------------------------------------------
    # E. medications — missing fields (Medication/MedicationDose parity)
    # ------------------------------------------------------------------
    op.add_column("medications", sa.Column("form", sa.String(20), nullable=False,
                                            server_default="pill"))
    op.add_column("medications", sa.Column("usage_instructions", sa.Text, nullable=True))
    op.add_column("medications", sa.Column("stock_count", sa.Integer, nullable=False,
                                            server_default="0"))
    op.add_column("medications", sa.Column("low_stock_threshold", sa.Integer, nullable=False,
                                            server_default="5"))

    # ------------------------------------------------------------------
    # Grants
    # ------------------------------------------------------------------
    for stmt in [
        "GRANT SELECT, INSERT, UPDATE, DELETE ON schedule_events TO parser_api_role",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON feed_posts TO parser_api_role",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON feed_comments TO parser_api_role",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON feed_reactions TO parser_api_role",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON caregiver_profiles TO parser_api_role",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON caregiver_checkins TO parser_api_role",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON caregiver_instructions TO parser_api_role",
    ]:
        op.execute(stmt)


def downgrade() -> None:
    for col in ("form", "usage_instructions", "stock_count", "low_stock_threshold"):
        op.drop_column("medications", col)

    op.drop_column("tasks", "origin")
    op.drop_column("tasks", "kind")

    op.drop_table("caregiver_instructions")
    op.drop_table("caregiver_checkins")
    op.drop_table("caregiver_profiles")

    op.drop_table("feed_reactions")
    op.drop_table("feed_comments")
    op.drop_table("feed_posts")

    op.drop_table("schedule_events")
