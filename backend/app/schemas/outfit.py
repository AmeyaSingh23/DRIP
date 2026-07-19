from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

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


class OutfitItemLayout(BaseModel):
    item_id: UUID
    zone: Literal["accessories", "shoes", "bottoms", "tops", "outerwear"]
    offset_x: float = Field(ge=-2000, le=2000)
    offset_y: float = Field(ge=-2000, le=2000)


class OutfitCreate(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    occasion: str | None = Field(default=None, max_length=50)
    item_ids: list[UUID] = Field(min_length=1, max_length=8)
    item_layout: list[OutfitItemLayout] = Field(default_factory=list, max_length=5)
    is_ai_generated: bool = True

    @field_validator("item_ids")
    @classmethod
    def unique_item_ids(cls, values: list[UUID]) -> list[UUID]:
        if len(set(values)) != len(values):
            raise ValueError("An outfit cannot contain the same item more than once")
        return values

    @model_validator(mode="after")
    def layout_references_outfit_items(self) -> "OutfitCreate":
        _validate_layout(self.item_layout, self.item_ids)
        return self


class OutfitUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    occasion: str | None = Field(default=None, max_length=50)
    item_ids: list[UUID] | None = Field(default=None, min_length=1, max_length=8)
    item_layout: list[OutfitItemLayout] | None = Field(default=None, max_length=5)

    @field_validator("item_ids")
    @classmethod
    def unique_item_ids(cls, values: list[UUID] | None) -> list[UUID] | None:
        if values is not None and len(set(values)) != len(values):
            raise ValueError("An outfit cannot contain the same item more than once")
        return values

    @model_validator(mode="after")
    def layout_has_unique_zones(self) -> "OutfitUpdate":
        if self.item_layout is not None:
            _validate_layout(self.item_layout, self.item_ids)
        return self


def _validate_layout(
    item_layout: list[OutfitItemLayout], item_ids: list[UUID] | None
) -> None:
    if len({entry.zone for entry in item_layout}) != len(item_layout):
        raise ValueError("Only one item can occupy each canvas zone")
    if item_ids is not None and any(entry.item_id not in item_ids for entry in item_layout):
        raise ValueError("Canvas layout includes an item outside this outfit")


class OutfitResponse(BaseModel):
    id: UUID
    name: str | None = None
    occasion: str | None = None
    is_ai_generated: bool
    created_at: datetime
    item_layout: list[OutfitItemLayout] = Field(default_factory=list)
    items: list[ClothingItemUploadResponse] = Field(default_factory=list)
