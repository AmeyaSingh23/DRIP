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
Identify only the most prominent garment. Use Custom only when there is no recognizable garment or it cannot fit a category.

Use exactly one broad category: Tops, Bottoms, Outerwear, Shoes, Dresses, Accessories, Uniform, or Custom.
Examples: T-shirt, polo, shirt, blouse, hoodie, and sweater are Tops. Shorts, boxer shorts, briefs, trousers, jeans, and skirts are Bottoms.
The item_name is specific (for example, "T-shirt", "US Polo Assn briefs", or "Checkered boxer shorts").
The color must be exactly one of: Black, White, Beige, Navy, Red, Green, Blue, Pink, Brown, Grey, Yellow, Purple, Orange, Multi, Other, or null.
Use Multi for a clearly multi-colour garment. Do not return descriptive shades such as "dusty pink" or "black and white".
Return only JSON matching the supplied schema. Never invent a brand, size, price, or personal detail."""

_CATEGORY_KEYWORDS: tuple[tuple[str, str], ...] = (
    ("Outerwear", "jacket coat blazer cardigan parka windbreaker"),
    ("Dresses", "dress gown jumpsuit romper"),
    ("Shoes", "shoe sneaker sandal slipper boot loafer heel"),
    ("Accessories", "belt cap hat scarf bag purse watch sunglasses"),
    ("Uniform", "uniform jersey scrubs"),
    ("Bottoms", "shorts short boxer brief underwear trunks pants trouser jeans skirt leggings jogger chinos"),
    ("Tops", "t-shirt tshirt tee shirt polo blouse tank top camisole hoodie sweater sweatshirt knitwear"),
)

_COLOR_KEYWORDS: tuple[tuple[str, str], ...] = (
    ("Multi", "multicolor multi-colour mixed"),
    ("Navy", "navy"),
    ("Black", "black charcoal"),
    ("White", "white ivory off-white"),
    ("Beige", "beige cream tan khaki"),
    ("Red", "red maroon burgundy wine"),
    ("Green", "green olive teal mint"),
    ("Blue", "blue cyan aqua"),
    ("Pink", "pink rose fuchsia magenta"),
    ("Brown", "brown mocha chocolate"),
    ("Grey", "grey gray silver"),
    ("Yellow", "yellow mustard gold"),
    ("Purple", "purple violet lavender lilac"),
    ("Orange", "orange coral peach"),
)


def _canonical(value: object, allowed: set[str], fallback: str | None = None) -> str | None:
    if not isinstance(value, str):
        return fallback
    candidate = value.strip().casefold()
    return next((item for item in allowed if item.casefold() == candidate), fallback)


def _contains_keyword(value: str, keywords: str) -> bool:
    padded = f" {value.casefold().replace('-', ' ').replace('/', ' ')} "
    return any(f" {keyword} " in padded for keyword in keywords.split())


def _infer_category(*values: object) -> str | None:
    text = " ".join(str(value) for value in values if isinstance(value, str))
    return next((category for category, keywords in _CATEGORY_KEYWORDS if _contains_keyword(text, keywords)), None)


def _normalize_color(value: object) -> str | None:
    exact = _canonical(value, _COLORS)
    if exact is not None:
        return exact
    if not isinstance(value, str):
        return None
    normalized = value.casefold().replace("-", " ").replace("/", " ")
    if any(phrase in normalized for phrase in ("black and white", "blue and white", "red and white", "multi color", "multi coloured")):
        return "Multi"
    return next((color for color, keywords in _COLOR_KEYWORDS if _contains_keyword(value, keywords)), None)


def _repair(raw: dict[str, object]) -> ClothingItemTags:
    raw_tags = raw.get("tags")
    tags = [str(tag).strip()[:50] for tag in raw_tags] if isinstance(raw_tags, list) else []
    item_name = str(raw["item_name"]).strip()[:120] if raw.get("item_name") else None
    category = _canonical(raw.get("category"), _CATEGORIES, "Custom") or "Custom"
    if category == "Custom":
        category = _infer_category(item_name, raw.get("custom_category"), *tags) or category
    try:
        confidence = min(1.0, max(0.0, float(raw.get("confidence", 0.0))))
    except (TypeError, ValueError):
        confidence = 0.0
    return ClothingItemTags(
        category=category,
        custom_category=str(raw["custom_category"]).strip()[:100] if category == "Custom" and raw.get("custom_category") else None,
        color=_normalize_color(raw.get("color")),
        pattern=_canonical(raw.get("pattern"), _PATTERNS),
        fabric=_canonical(raw.get("fabric"), _FABRICS),
        is_uniform=category == "Uniform",
        item_name=item_name,
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
