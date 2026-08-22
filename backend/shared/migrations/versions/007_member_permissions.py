"""add permissions column to household_members

Revision ID: 007
Revises: 006
Create Date: 2026-08-20
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "007"
down_revision: Union[str, None] = "006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "household_members",
        sa.Column("permissions", postgresql.JSONB, nullable=True),
    )


def downgrade() -> None:
    op.drop_column("household_members", "permissions")
