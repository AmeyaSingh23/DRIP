"""add archive state for wardrobe items and outfits

Revision ID: 20260720_07
Revises: 20260719_06
Create Date: 2026-07-20
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260720_07"
down_revision: Union[str, Sequence[str], None] = "20260719_06"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_index("ix_clothing_items_user_active", table_name="clothing_items")
    op.drop_index("ix_clothing_items_user_category_active", table_name="clothing_items")
    op.alter_column("clothing_items", "deleted_at", new_column_name="archived_at")
    op.create_index("ix_clothing_items_user_archived", "clothing_items", ["user_id", "archived_at"])
    op.create_index("ix_clothing_items_user_category_archived", "clothing_items", ["user_id", "category", "archived_at"])
    op.add_column("outfits", sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index("ix_outfits_user_archived", "outfits", ["user_id", "archived_at"])


def downgrade() -> None:
    op.drop_index("ix_outfits_user_archived", table_name="outfits")
    op.drop_column("outfits", "archived_at")
    op.drop_index("ix_clothing_items_user_category_archived", table_name="clothing_items")
    op.drop_index("ix_clothing_items_user_archived", table_name="clothing_items")
    op.alter_column("clothing_items", "archived_at", new_column_name="deleted_at")
    op.create_index("ix_clothing_items_user_category_active", "clothing_items", ["user_id", "category", "deleted_at"])
    op.create_index("ix_clothing_items_user_active", "clothing_items", ["user_id", "deleted_at"])
