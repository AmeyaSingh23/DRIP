"""create wardrobe schema

Revision ID: 20260718_02
Revises: 20260717_01
Create Date: 2026-07-18
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "20260718_02"
down_revision: Union[str, Sequence[str], None] = "20260717_01"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "clothing_items",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("cloudinary_url", sa.Text(), nullable=False),
        sa.Column("cloudinary_public_id", sa.String(length=255), nullable=False),
        sa.Column("category", sa.String(length=50), nullable=False),
        sa.Column("custom_category", sa.String(length=100), nullable=True),
        sa.Column("color", sa.String(length=50), nullable=True),
        sa.Column("pattern", sa.String(length=50), nullable=True),
        sa.Column("fabric", sa.String(length=50), nullable=True),
        sa.Column("is_uniform", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("item_name", sa.String(length=120), nullable=True),
        sa.Column("tags", postgresql.ARRAY(sa.String(length=50)), nullable=False, server_default=sa.text("'{}'::varchar[]")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_clothing_items_user_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_clothing_items"),
    )
    op.create_index("ix_clothing_items_user_id", "clothing_items", ["user_id"])
    op.create_index("ix_clothing_items_user_active", "clothing_items", ["user_id", "deleted_at"])
    op.create_index("ix_clothing_items_user_category_active", "clothing_items", ["user_id", "category", "deleted_at"])

    op.create_table(
        "outfits",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=True),
        sa.Column("occasion", sa.String(length=50), nullable=True),
        sa.Column("is_ai_generated", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_outfits_user_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_outfits"),
    )
    op.create_index("ix_outfits_user_id", "outfits", ["user_id"])
    op.create_index("ix_outfits_user_created_at", "outfits", ["user_id", "created_at"])

    op.create_table(
        "outfit_items",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("outfit_id", sa.Uuid(), nullable=False),
        sa.Column("clothing_item_id", sa.Uuid(), nullable=False),
        sa.Column("display_order", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(["clothing_item_id"], ["clothing_items.id"], name="fk_outfit_items_clothing_item_id_clothing_items", ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["outfit_id"], ["outfits.id"], name="fk_outfit_items_outfit_id_outfits", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_outfit_items"),
        sa.UniqueConstraint("outfit_id", "clothing_item_id", name="uq_outfit_items_outfit_item"),
        sa.UniqueConstraint("outfit_id", "display_order", name="uq_outfit_items_outfit_order"),
    )
    op.create_index("ix_outfit_items_outfit_id", "outfit_items", ["outfit_id"])
    op.create_index("ix_outfit_items_clothing_item_id", "outfit_items", ["clothing_item_id"])

    op.create_table(
        "calendar_entries",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("outfit_id", sa.Uuid(), nullable=True),
        sa.Column("entry_date", sa.Date(), nullable=False),
        sa.Column("slot", sa.String(length=32), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.CheckConstraint("slot IN ('morning_college', 'afternoon', 'evening', 'night')", name="ck_calendar_entries_slot"),
        sa.ForeignKeyConstraint(["outfit_id"], ["outfits.id"], name="fk_calendar_entries_outfit_id_outfits", ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_calendar_entries_user_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_calendar_entries"),
        sa.UniqueConstraint("user_id", "entry_date", "slot", name="uq_calendar_entries_user_date_slot"),
    )
    op.create_index("ix_calendar_entries_user_id", "calendar_entries", ["user_id"])
    op.create_index("ix_calendar_entries_outfit_id", "calendar_entries", ["outfit_id"])
    op.create_index("ix_calendar_entries_user_date", "calendar_entries", ["user_id", "entry_date"])


def downgrade() -> None:
    op.drop_index("ix_calendar_entries_user_date", table_name="calendar_entries")
    op.drop_index("ix_calendar_entries_outfit_id", table_name="calendar_entries")
    op.drop_index("ix_calendar_entries_user_id", table_name="calendar_entries")
    op.drop_table("calendar_entries")
    op.drop_index("ix_outfit_items_clothing_item_id", table_name="outfit_items")
    op.drop_index("ix_outfit_items_outfit_id", table_name="outfit_items")
    op.drop_table("outfit_items")
    op.drop_index("ix_outfits_user_created_at", table_name="outfits")
    op.drop_index("ix_outfits_user_id", table_name="outfits")
    op.drop_table("outfits")
    op.drop_index("ix_clothing_items_user_category_active", table_name="clothing_items")
    op.drop_index("ix_clothing_items_user_active", table_name="clothing_items")
    op.drop_index("ix_clothing_items_user_id", table_name="clothing_items")
    op.drop_table("clothing_items")
