from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

CalendarSlot = Literal["morning_college", "afternoon", "evening", "night"]


class CalendarEntryUpsert(BaseModel):
    entry_date: date
    slot: CalendarSlot
    outfit_id: UUID | None = None
    notes: str | None = Field(default=None, max_length=1000)


class CalendarEntryResponse(BaseModel):
    id: UUID
    entry_date: date
    slot: CalendarSlot
    outfit_id: UUID | None = None
    outfit_name: str | None = None
    notes: str | None = None
    created_at: datetime
