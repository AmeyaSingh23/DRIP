from __future__ import annotations

from datetime import date, datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Index, String, Text, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class CalendarEntry(Base):
    __tablename__ = "calendar_entries"
    __table_args__ = (
        UniqueConstraint("user_id", "entry_date", "slot", name="uq_calendar_entries_user_date_slot"),
        CheckConstraint(
            "slot IN ('morning_college', 'afternoon', 'evening', 'night')",
            name="ck_calendar_entries_slot",
        ),
        Index("ix_calendar_entries_user_date", "user_id", "entry_date"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    # A removed outfit leaves the planning slot and its notes intact.
    outfit_id: Mapped[UUID | None] = mapped_column(ForeignKey("outfits.id", ondelete="SET NULL"), nullable=True, index=True)
    entry_date: Mapped[date] = mapped_column(Date, nullable=False)
    slot: Mapped[str] = mapped_column(String(32), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP"))
