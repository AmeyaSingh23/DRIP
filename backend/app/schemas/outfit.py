from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from app.schemas.clothing_item import ClothingItemUploadResponse


class OutfitGenerateRequest(BaseModel):
    occasion: str | None = Field(default=None, max_length=50)
    style_notes: str | None = Field(default=None, max_length=240)
    weather_summary: str | None = Field(default=None, max_length=120)


class OutfitPreview(BaseModel):
    name: str = Field(max_length=120)
    occasion: str | None = Field(default=None, max_length=50)
    rationale: str = Field(max_length=400)
    item_ids: list[UUID] = Field(min_length=1, max_length=8)
    items: list[ClothingItemUploadResponse] = Field(default_factory=list)


class OutfitCreate(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    occasion: str | None = Field(default=None, max_length=50)
    item_ids: list[UUID] = Field(min_length=1, max_length=8)
    is_ai_generated: bool = True

    @field_validator("item_ids")
    @classmethod
    def unique_item_ids(cls, values: list[UUID]) -> list[UUID]:
        if len(set(values)) != len(values):
            raise ValueError("An outfit cannot contain the same item more than once")
        return values


class OutfitResponse(BaseModel):
    id: UUID
    name: str | None = None
    occasion: str | None = None
    is_ai_generated: bool
    created_at: datetime
    items: list[ClothingItemUploadResponse] = Field(default_factory=list)
