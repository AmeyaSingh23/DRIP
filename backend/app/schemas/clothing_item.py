from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ClothingItemTags(BaseModel):
    is_clothing_item: bool = False
    is_worn_on_person: bool = False
    category: str = "Custom"
    custom_category: str | None = None
    color: str | None = None
    pattern: str | None = None
    fabric: str | None = None
    is_uniform: bool = False
    item_name: str | None = None
    tags: list[str] = Field(default_factory=list, max_length=20)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)


class ClothingItemUpdate(BaseModel):
    category: str | None = Field(default=None, max_length=50)
    custom_category: str | None = Field(default=None, max_length=100)
    color: str | None = Field(default=None, max_length=50)
    pattern: str | None = Field(default=None, max_length=50)
    fabric: str | None = Field(default=None, max_length=50)
    is_uniform: bool | None = None
    item_name: str | None = Field(default=None, max_length=120)
    tags: list[str] | None = Field(default=None, max_length=20)


class ClothingItemUploadResponse(ClothingItemTags):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    cloudinary_url: str
    cloudinary_public_id: str
    ai_confidence: float = Field(ge=0.0, le=1.0)
    user_verified: bool
    created_at: datetime
    archived_at: datetime | None = None


class OutfitUsage(BaseModel):
    outfit_id: UUID
    outfit_name: str | None = None


class CalendarUsage(BaseModel):
    entry_date: date
    slot: str
    outfit_id: UUID
    outfit_name: str | None = None


class ClothingItemUsageResponse(BaseModel):
    outfit_count: int = Field(ge=0)
    outfits: list[OutfitUsage] = Field(default_factory=list)
    calendar_history: list[CalendarUsage] = Field(default_factory=list)
