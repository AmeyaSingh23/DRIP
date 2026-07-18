"""add item confidence and verification

Revision ID: 20260718_03
Revises: 20260718_02
Create Date: 2026-07-18
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260718_03"
down_revision: Union[str, Sequence[str], None] = "20260718_02"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "clothing_items",
        sa.Column("ai_confidence", sa.Float(), nullable=False, server_default=sa.text("0")),
    )
    op.add_column(
        "clothing_items",
        sa.Column("user_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )
    op.add_column("clothing_items", sa.Column("user_verified_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column("clothing_items", "user_verified_at")
    op.drop_column("clothing_items", "user_verified")
    op.drop_column("clothing_items", "ai_confidence")
