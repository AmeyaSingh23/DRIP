from __future__ import annotations

import asyncio
import base64
import json

from fastapi import HTTPException, status
from google import genai

from app.core.config import get_settings
from app.schemas.clothing_item import ClothingItemTags

_CATEGORIES = {"Tops", "Bottoms", "Outerwear", "Shoes", "Dresses", "Accessories", "Uniform", "Custom"}
_COLORS = {"Black", "White", "Beige", "Navy", "Red", "Green", "Blue", "Pink", "Brown", "Grey", "Yellow", "Purple", "Orange", "Multi", "Other"}
_PATTERNS = {"Solid", "Striped", "Floral", "Checkered", "Animal Print", "Graphic", "Abstract", "Other"}
_FABRICS = {"Denim", "Knit", "Cotton", "Silk", "Linen", "Leather", "Synthetic", "Wool", "Corduroy", "Other"}

_PROMPT = """You are a fashion item classifier. Identify the one main clothing item in this image. Return only JSON matching the supplied schema. Use Custom and confidence below 0.6 when uncertain. Never invent brands or personal details."""


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
                    {"type": "image", "data": base64.b64encode(image_bytes).decode("ascii"), "mime_type": mime_type},
                ],
                response_format={"type": "text", "mime_type": "application/json", "schema": ClothingItemTags.model_json_schema()},
            )
            return interaction.output_text

        try:
            response_text = await asyncio.to_thread(request)
        except Exception as error:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Gemini tagging is temporarily unavailable") from error
        try:
            parsed = json.loads(response_text)
        except json.JSONDecodeError:
            return ClothingItemTags()
        return _repair(parsed if isinstance(parsed, dict) else {})
