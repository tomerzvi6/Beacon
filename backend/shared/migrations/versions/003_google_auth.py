"""Phase 9.1.5: add Google identity provider — google_user_id column,
relax apple_user_id NOT NULL.

Revision ID: 003
Revises: 002
Create Date: 2026-04-29
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # apple_user_id becomes nullable so Google-only users can exist
    op.alter_column("users", "apple_user_id", existing_type=sa.String(128), nullable=True)

    op.add_column("users", sa.Column("google_user_id", sa.String(128), nullable=True))
    op.create_unique_constraint("uq_users_google_user_id", "users", ["google_user_id"])


def downgrade() -> None:
    op.drop_constraint("uq_users_google_user_id", "users", type_="unique")
    op.drop_column("users", "google_user_id")
    # NOTE: this will fail if any user row has apple_user_id IS NULL.
    # Operators must reconcile Google-only users before downgrading.
    op.alter_column("users", "apple_user_id", existing_type=sa.String(128), nullable=False)
