from __future__ import annotations

import asyncio
import base64
import json

from fastapi import HTTPException, status
from google import genai
from google.genai.errors import APIError

from app.core.config import get_settings
from app.schemas.clothing_item import ClothingItemTags

_CATEGORIES = {"Tops", "Bottoms", "Outerwear", "Shoes", "Dresses", "Accessories", "Uniform", "Custom"}
_COLORS = {"Black", "White", "Beige", "Navy", "Red", "Green", "Blue", "Pink", "Brown", "Grey", "Yellow", "Purple", "Orange", "Multi", "Other"}
_PATTERNS = {"Solid", "Striped", "Floral", "Checkered", "Animal Print", "Graphic", "Abstract", "Other"}
_FABRICS = {"Denim", "Knit", "Cotton", "Silk", "Linen", "Leather", "Synthetic", "Wool", "Corduroy", "Other"}

_PROMPT = """Classify the single primary garment in this photo for a personal wardrobe.
Ignore bedsheets, furniture, hands, legs, shoes, camera equipment, text, and every non-garment object.
Identify only the most prominent garment; if there are multiple garments or no clear garment, use Custom with confidence below 0.6.
Return only JSON matching the supplied schema. Never invent a brand, size, price, or personal detail."""


def _canonical(value: object, allowed: set[str], fallback: str | None = None) -> str | None:
    if not isinstance(value, str):
        return fallback
    candidate = value.strip().casefold()
    return next((item for item in allowed if item.casefold() == candidate), fallback)


def _repair(raw: dict[str, object]) -> ClothingItemTags:
    category = _canonical(raw.get("category"), _CATEGORIES, "Custom") or "Custom"
    raw_tags = raw.get("tags")
    tags = [str(tag).strip()[:50] for tag in raw_tags] if isinstance(raw_tags, list) else []
    try:
        confidence = min(1.0, max(0.0, float(raw.get("confidence", 0.0))))
    except (TypeError, ValueError):
        confidence = 0.0
    return ClothingItemTags(
        category=category,
        custom_category=str(raw["custom_category"]).strip()[:100] if category == "Custom" and raw.get("custom_category") else None,
        color=_canonical(raw.get("color"), _COLORS),
        pattern=_canonical(raw.get("pattern"), _PATTERNS),
        fabric=_canonical(raw.get("fabric"), _FABRICS),
        is_uniform=category == "Uniform",
        item_name=str(raw["item_name"]).strip()[:120] if raw.get("item_name") else None,
        tags=tags[:20],
        confidence=confidence,
    )


class GeminiTagger:
    def __init__(self) -> None:
        settings = get_settings()
        if not settings.gemini_api_key:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Gemini is not configured on the server")
        self._client = genai.Client(api_key=settings.gemini_api_key)
        self._model = settings.gemini_model

    async def tag(self, image_bytes: bytes, mime_type: str) -> ClothingItemTags:
        def request() -> str:
            interaction = self._client.interactions.create(
                model=self._model,
                input=[
                    {"type": "text", "text": _PROMPT},
                    {
                        "type": "image",
                        "data": base64.b64encode(image_bytes).decode("ascii"),
                        "mime_type": mime_type,
                        "resolution": "high",
                    },
                ],
                response_format={"type": "text", "mime_type": "application/json", "schema": ClothingItemTags.model_json_schema()},
            )
            return interaction.output_text

        response_text: str | None = None
        for attempt in range(3):
            try:
                response_text = await asyncio.to_thread(request)
                break
            except APIError as error:
                if error.code in {429, 500, 502, 503, 504} and attempt < 2:
                    await asyncio.sleep(2 ** attempt)
                    continue
                if error.code == 429:
                    raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Gemini is temporarily busy. Please wait a moment and try again.") from error
                raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Gemini tagging is temporarily unavailable") from error
            except Exception as error:
                raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Gemini tagging is temporarily unavailable") from error
        try:
            parsed = json.loads(response_text)
        except (TypeError, json.JSONDecodeError):
            return ClothingItemTags()
        return _repair(parsed if isinstance(parsed, dict) else {})
