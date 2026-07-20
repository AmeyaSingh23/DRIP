from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String, Text, text
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ClothingItem(Base):
    __tablename__ = "clothing_items"
    __table_args__ = (
        Index("ix_clothing_items_user_archived", "user_id", "archived_at"),
        Index("ix_clothing_items_user_category_archived", "user_id", "category", "archived_at"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    cloudinary_url: Mapped[str] = mapped_column(Text, nullable=False)
    cloudinary_public_id: Mapped[str] = mapped_column(String(255), nullable=False)
    category: Mapped[str] = mapped_column(String(50), nullable=False)
    custom_category: Mapped[str | None] = mapped_column(String(100), nullable=True)
    color: Mapped[str | None] = mapped_column(String(50), nullable=True)
    pattern: Mapped[str | None] = mapped_column(String(50), nullable=True)
    fabric: Mapped[str | None] = mapped_column(String(50), nullable=True)
    is_uniform: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    item_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    tags: Mapped[list[str]] = mapped_column(ARRAY(String(50)), nullable=False, server_default=text("'{}'::varchar[]"))
    ai_confidence: Mapped[float] = mapped_column(nullable=False, server_default=text("0"))
    user_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    user_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP"))
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
