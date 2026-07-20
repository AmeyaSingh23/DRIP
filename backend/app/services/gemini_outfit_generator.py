from __future__ import annotations

import asyncio
import json
from uuid import UUID

from fastapi import HTTPException, status
from google import genai
from google.genai.errors import APIError
from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.db.models.clothing_item import ClothingItem
from app.schemas.outfit import OutfitWeatherContext


class OutfitSuggestion(BaseModel):
    name: str = Field(max_length=120)
    rationale: str = Field(max_length=400)
    item_ids: list[UUID] = Field(min_length=1, max_length=8)


class GeminiOutfitGenerator:
    def __init__(self) -> None:
        settings = get_settings()
        if not settings.gemini_api_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Gemini is not configured on the server",
            )
        self._client = genai.Client(api_key=settings.gemini_api_key)
        self._model = settings.gemini_model

    async def generate(
        self,
        items: list[ClothingItem],
        *,
        occasion: str | None,
        style_notes: str | None,
        weather_context: OutfitWeatherContext | None,
    ) -> OutfitSuggestion:
        inventory = [
            {
                "id": str(item.id),
                "name": item.item_name,
                "category": item.category,
                "custom_category": item.custom_category,
                "color": item.color,
                "pattern": item.pattern,
                "fabric": item.fabric,
                "tags": item.tags,
            }
            for item in items
        ]
        prompt = f"""Create one wearable outfit using only IDs from the inventory JSON below.
Return a concise name, a concise rationale, and 1-8 distinct item IDs.
Prefer a coherent primary garment combination (top+bottom, dress, or uniform) and add shoes/accessories only when available and complementary.
Never invent garments, IDs, brands, weather facts, or missing items.
Occasion: {occasion or 'not specified'}
Style notes: {style_notes or 'not specified'}
Weather context: {json.dumps(weather_context.model_dump(mode='json'), separators=(',', ':')) if weather_context else 'not available; do not assume weather conditions'}
Inventory: {json.dumps(inventory, separators=(',', ':'))}"""

        def request() -> str:
            interaction = self._client.interactions.create(
                model=self._model,
                input=[{"type": "text", "text": prompt}],
                response_format={
                    "type": "text",
                    "mime_type": "application/json",
                    "schema": OutfitSuggestion.model_json_schema(),
                },
            )
            return interaction.output_text

        response_text: str | None = None
        for attempt in range(2):
            try:
                response_text = await asyncio.wait_for(asyncio.to_thread(request), timeout=30)
                break
            except TimeoutError as error:
                if attempt == 0:
                    await asyncio.sleep(1)
                    continue
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail="Gemini outfit generation is temporarily unavailable",
                ) from error
            except APIError as error:
                if error.code in {429, 500, 502, 503, 504} and attempt == 0:
                    await asyncio.sleep(1)
                    continue
                if error.code == 429:
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="Gemini is temporarily busy. Please wait a moment and try again.",
                    ) from error
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail="Gemini outfit generation is temporarily unavailable",
                ) from error
            except Exception as error:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail="Gemini outfit generation is temporarily unavailable",
                ) from error
        try:
            return OutfitSuggestion.model_validate_json(response_text)
        except (TypeError, ValueError) as error:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Gemini returned an invalid outfit suggestion. Please try again.",
            ) from error
