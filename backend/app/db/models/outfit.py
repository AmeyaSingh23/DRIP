from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Outfit(Base):
    __tablename__ = "outfits"
    __table_args__ = (Index("ix_outfits_user_created_at", "user_id", "created_at"),)

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    occasion: Mapped[str | None] = mapped_column(String(50), nullable=True)
    is_ai_generated: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP"))


class OutfitItem(Base):
    __tablename__ = "outfit_items"
    __table_args__ = (
        UniqueConstraint("outfit_id", "clothing_item_id", name="uq_outfit_items_outfit_item"),
        UniqueConstraint("outfit_id", "display_order", name="uq_outfit_items_outfit_order"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    outfit_id: Mapped[UUID] = mapped_column(ForeignKey("outfits.id", ondelete="CASCADE"), nullable=False, index=True)
    # No cascade: soft-deleted clothes remain available to historical flatlays.
    clothing_item_id: Mapped[UUID] = mapped_column(ForeignKey("clothing_items.id", ondelete="RESTRICT"), nullable=False, index=True)
    display_order: Mapped[int] = mapped_column(Integer, nullable=False)
