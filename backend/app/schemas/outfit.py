from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

from app.schemas.clothing_item import ClothingItemUploadResponse


class OutfitLocation(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class OutfitWeatherContext(BaseModel):
    location_name: str
    local_time: datetime
    time_of_day: Literal["morning", "afternoon", "evening", "night"]
    condition: str
    temperature_c: float
    apparent_temperature_c: float
    precipitation_probability: int | None = Field(default=None, ge=0, le=100)
    precipitation_mm: float | None = Field(default=None, ge=0)
    humidity_percent: int | None = Field(default=None, ge=0, le=100)
    wind_speed_kmh: float | None = Field(default=None, ge=0)
    wind_gusts_kmh: float | None = Field(default=None, ge=0)
    considerations: list[str] = Field(default_factory=list)


class OutfitWeatherContextRequest(BaseModel):
    location: OutfitLocation
    wear_at: datetime


class OutfitWeatherContextResponse(BaseModel):
    status: Literal["available", "unavailable"]
    weather_context: OutfitWeatherContext | None = None


class OutfitGenerateRequest(BaseModel):
    occasion: str | None = Field(default=None, max_length=50)
    style_notes: str | None = Field(default=None, max_length=240)
    location: OutfitLocation | None = None
    wear_at: datetime | None = None
    # Kept for older clients. New clients use a trusted backend weather lookup.
    weather_summary: str | None = Field(default=None, max_length=120)

    @model_validator(mode="after")
    def weather_location_is_complete(self) -> "OutfitGenerateRequest":
        if (self.location is None) != (self.wear_at is None):
            raise ValueError("location and wear_at must be provided together")
        return self


class OutfitPreview(BaseModel):
    name: str = Field(max_length=120)
    occasion: str | None = Field(default=None, max_length=50)
    rationale: str = Field(max_length=400)
    item_ids: list[UUID] = Field(min_length=1, max_length=8)
    items: list[ClothingItemUploadResponse] = Field(default_factory=list)
    weather_status: Literal["available", "unavailable", "not_requested"] = "not_requested"
    weather_context: OutfitWeatherContext | None = None
    is_quick_pick: bool = False


class OutfitItemLayout(BaseModel):
    item_id: UUID
    zone: Literal["accessories", "shoes", "bottoms", "tops", "outerwear"]
    offset_x: float = Field(ge=-2000, le=2000)
    offset_y: float = Field(ge=-2000, le=2000)
    scale: float = Field(default=1.0, ge=0.4, le=2.4)


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
    archived_at: datetime | None = None
    item_layout: list[OutfitItemLayout] = Field(default_factory=list)
    items: list[ClothingItemUploadResponse] = Field(default_factory=list)
