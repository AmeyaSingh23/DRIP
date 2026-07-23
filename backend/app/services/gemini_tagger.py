from __future__ import annotations

import asyncio
import base64
import json
import logging
from dataclasses import dataclass, field
from datetime import date, timezone
from datetime import datetime as dt

from fastapi import HTTPException, status  # type: ignore
from google import genai  # type: ignore
from google.genai import types  # type: ignore
from google.genai.errors import APIError  # type: ignore

from app.core.config import get_settings
from app.schemas.clothing_item import ClothingItemTags

_CATEGORIES = {"Tops", "Bottoms", "Outerwear", "Shoes", "Dresses", "Accessories", "Uniform", "Custom"}
_COLORS = {"Black", "White", "Beige", "Navy", "Red", "Green", "Blue", "Pink", "Brown", "Grey", "Yellow", "Purple", "Orange", "Multi", "Other"}
_PATTERNS = {"Solid", "Striped", "Floral", "Checkered", "Animal Print", "Graphic", "Abstract", "Other"}
_FABRICS = {"Denim", "Knit", "Cotton", "Silk", "Linen", "Leather", "Synthetic", "Wool", "Corduroy", "Other"}
logger = logging.getLogger(__name__)

_PROMPT = """First decide whether this photo contains one recognizable clothing item suitable for a personal wardrobe.
Ignore bedsheets, furniture, hands, legs, shoes, camera equipment, text, and every non-garment object.
Identify only the most prominent garment. Use Custom only when there is no recognizable garment or it cannot fit a category.

Set is_clothing_item to false for animals, people, faces, food, rooms, screenshots, scenery, or any image without a garment. Do not classify a non-garment as Custom.
Set is_clothing_item to true only when a garment is visibly present, even if its background is poor.
Set is_worn_on_person to true when the prominent garment is being worn by a visible person or mannequin. A flat-lay, hanger, or product-only photo is false.

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


# ---------------------------------------------------------------------------
# Key pool — module-level, survives across requests within one process
# ---------------------------------------------------------------------------

@dataclass
class _KeyState:
    daily_exhausted: bool = False
    exhausted_date: date | None = None


@dataclass
class _KeyPool:
    """Tracks per-key daily-exhaustion state for Gemini API keys."""

    keys: list[str] = field(default_factory=list)
    _states: list[_KeyState] = field(default_factory=list, init=False, repr=False)

    def __post_init__(self) -> None:
        self._states = [_KeyState() for _ in self.keys]

    @property
    def is_configured(self) -> bool:
        return len(self.keys) > 0

    def available_keys(self) -> list[tuple[int, str]]:
        """Return (index, key) pairs for keys not marked exhausted today."""
        today = dt.now(timezone.utc).date()
        available: list[tuple[int, str]] = []
        for index, (key, key_state) in enumerate(zip(self.keys, self._states)):
            if key_state.daily_exhausted and key_state.exhausted_date == today:
                continue
            # Auto-clear stale exhaustion from a previous day.
            if key_state.daily_exhausted and key_state.exhausted_date != today:
                key_state.daily_exhausted = False
                key_state.exhausted_date = None
            available.append((index, key))
        return available

    def mark_daily_exhausted(self, index: int) -> None:
        today = dt.now(timezone.utc).date()
        state = self._states[index]
        state.daily_exhausted = True
        state.exhausted_date = today
        logger.info("Gemini key %d marked daily-exhausted for %s", index + 1, today)


def _build_key_pool() -> _KeyPool:
    settings = get_settings()
    keys = settings.gemini_api_keys
    if not keys:
        logger.warning("No Gemini API keys configured — auto-tagging is disabled")
    return _KeyPool(keys=keys)


_key_pool = _build_key_pool()


# ---------------------------------------------------------------------------
# Error classification — uses structured details, not message text
# ---------------------------------------------------------------------------

_DAILY_RETRY_THRESHOLD_SECONDS = 300  # 5 minutes


def _classify_error(error: APIError) -> str:
    """Classify a Gemini APIError into an actionable category.

    Returns one of: ``daily_exhausted``, ``short_limit``, ``overloaded``,
    ``invalid_request``, ``config_error``, ``other``.
    """
    code = getattr(error, "code", None)

    if code == 400:
        return "invalid_request"
    if code in {401, 403}:
        return "config_error"
    if code == 503:
        return "overloaded"

    if code == 429:
        # Attempt structured detail inspection first.
        details = getattr(error, "details", None)
        if isinstance(details, (list, tuple)):
            for detail_item in details:
                if not isinstance(detail_item, dict):
                    continue
                at_type = str(detail_item.get("@type", ""))

                # QuotaFailure → check quotaId in violations.
                if "QuotaFailure" in at_type:
                    violations = detail_item.get("violations", [])
                    if isinstance(violations, (list, tuple)):
                        for violation in violations:
                            if not isinstance(violation, dict):
                                continue
                            quota_id = str(violation.get("quotaId", "")).casefold()
                            if "perday" in quota_id:
                                return "daily_exhausted"
                            if "perminute" in quota_id:
                                return "short_limit"

                # RetryInfo → check retryDelay duration.
                if "RetryInfo" in at_type:
                    retry_delay = detail_item.get("retryDelay")
                    seconds = _parse_duration_seconds(retry_delay)
                    if seconds is not None and seconds >= _DAILY_RETRY_THRESHOLD_SECONDS:
                        return "daily_exhausted"
                    return "short_limit"

        # No structured details available — treat as short-term limit.
        return "short_limit"

    return "other"


def _parse_duration_seconds(value: object) -> float | None:
    """Parse a protobuf-style duration string like ``'3600s'`` into seconds."""
    if not isinstance(value, str):
        return None
    value = value.strip().rstrip("s").strip()
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------------------
# Tag repair helpers (unchanged)
# ---------------------------------------------------------------------------

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
    is_clothing_item = raw.get("is_clothing_item") is True
    if not is_clothing_item:
        return ClothingItemTags(is_clothing_item=False, confidence=confidence)
    return ClothingItemTags(
        is_clothing_item=True,
        is_worn_on_person=raw.get("is_worn_on_person") is True,
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


# ---------------------------------------------------------------------------
# GeminiTagger — public interface unchanged
# ---------------------------------------------------------------------------

class GeminiTagger:
    def __init__(self) -> None:
        if not _key_pool.is_configured:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Auto-tagging is temporarily unavailable.")
        self._model = get_settings().gemini_model

    async def tag(self, image_bytes: bytes, mime_type: str) -> ClothingItemTags:
        available = _key_pool.available_keys()
        if not available:
            logger.warning("All Gemini keys daily-exhausted")
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Auto-tagging is unavailable today. You can add details manually or try again tomorrow.",
            )

        image_b64 = base64.b64encode(image_bytes).decode("ascii")
        all_daily = True  # Track whether every failure was daily exhaustion.

        for key_index, api_key in available:
            client = genai.Client(
                api_key=api_key,
                http_options=types.HttpOptions(
                    retryOptions=types.HttpRetryOptions(
                        attempts=1,
                        httpStatusCodes=[],
                    ),
                ),
            )

            def request() -> str:
                interaction = client.interactions.create(
                    model=self._model,
                    input=[
                        {"type": "text", "text": _PROMPT},
                        {
                            "type": "image",
                            "data": image_b64,
                            "mime_type": mime_type,
                            "resolution": "high",
                        },
                    ],
                    response_format={"type": "text", "mime_type": "application/json", "schema": ClothingItemTags.model_json_schema()},
                )
                return interaction.output_text

            try:
                response_text = await asyncio.to_thread(request)
            except APIError as error:
                classification = _classify_error(error)
                logger.warning("Gemini key %d error: code=%s classification=%s", key_index + 1, error.code, classification)

                if classification == "invalid_request":
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail="Auto-tagging could not process this image. Try a different photo or add details manually.",
                    )

                if classification == "config_error":
                    raise HTTPException(
                        status_code=status.HTTP_502_BAD_GATEWAY,
                        detail="Auto-tagging is temporarily unavailable.",
                    )

                if classification == "daily_exhausted":
                    _key_pool.mark_daily_exhausted(key_index)
                    continue

                # short_limit, overloaded, other — move to next key.
                all_daily = False
                continue
            except Exception as error:
                logger.warning("Gemini key %d unexpected error: %s", key_index + 1, type(error).__name__)
                all_daily = False
                continue

            # Success — parse the response.
            try:
                parsed = json.loads(response_text)
            except (TypeError, json.JSONDecodeError):
                return ClothingItemTags()
            return _repair(parsed if isinstance(parsed, dict) else {})

        # All available keys failed.
        if all_daily:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Auto-tagging is unavailable today. You can add details manually or try again tomorrow.",
            )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Auto-tagging is temporarily unavailable. Try again shortly or add details manually.",
            headers={"Retry-After": "5"},
        )
