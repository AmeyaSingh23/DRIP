from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from io import BytesIO
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from PIL import Image, UnidentifiedImageError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.db.models.clothing_item import ClothingItem
from app.db.models.user import User
from app.schemas.clothing_item import ClothingItemUpdate, ClothingItemUploadResponse
from app.services.cloudinary_service import CloudinaryService
from app.services.gemini_tagger import GeminiTagger

router = APIRouter()
_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}


def _validate_image(data: bytes, content_type: str | None, limit: int, label: str) -> str:
    if not data or len(data) > limit:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail=f"{label} is too large")
    if content_type not in _IMAGE_TYPES:
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail=f"{label} must be JPEG, PNG, or WebP")
    try:
        with Image.open(BytesIO(data)) as image:
            image.verify()
    except (UnidentifiedImageError, OSError):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=f"{label} is not a valid image") from None
    return content_type


def _response(item: ClothingItem) -> ClothingItemUploadResponse:
    return ClothingItemUploadResponse(
        id=item.id,
        cloudinary_url=item.cloudinary_url,
        cloudinary_public_id=item.cloudinary_public_id,
        created_at=item.created_at,
        category=item.category,
        custom_category=item.custom_category,
        color=item.color,
        pattern=item.pattern,
        fabric=item.fabric,
        is_uniform=item.is_uniform,
        item_name=item.item_name,
        tags=item.tags,
        confidence=item.ai_confidence,
        ai_confidence=item.ai_confidence,
        user_verified=item.user_verified,
    )


@router.post("/upload", response_model=ClothingItemUploadResponse, status_code=status.HTTP_201_CREATED)
async def upload_item(
    cutout: UploadFile = File(...),
    tagging_image: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> ClothingItemUploadResponse:
    cutout_bytes, tagging_bytes = await asyncio.gather(cutout.read(), tagging_image.read())
    cutout_type = _validate_image(cutout_bytes, cutout.content_type, 20 * 1024 * 1024, "Cutout")
    tagging_type = _validate_image(tagging_bytes, tagging_image.content_type, 4 * 1024 * 1024, "Tagging image")
    if cutout_type != "image/png":
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Cutout must be a transparent PNG")

    cloudinary = CloudinaryService()
    try:
        # Tag first. This avoids uploading orphaned Cloudinary assets whenever
        # the AI provider is delayed or rate-limited.
        tags = await GeminiTagger().tag(tagging_bytes, tagging_type)
        cloudinary_result = await cloudinary.upload_cutout(cutout_bytes, current_user.id)
    except Exception:
        raise
    cloudinary_url, public_id = cloudinary_result
    item = ClothingItem(
        user_id=current_user.id,
        cloudinary_url=cloudinary_url,
        cloudinary_public_id=public_id,
        category=tags.category,
        custom_category=tags.custom_category,
        color=tags.color,
        pattern=tags.pattern,
        fabric=tags.fabric,
        is_uniform=tags.is_uniform,
        item_name=tags.item_name,
        tags=tags.tags,
        ai_confidence=tags.confidence,
    )
    try:
        session.add(item)
        await session.commit()
        await session.refresh(item)
    except Exception:
        await session.rollback()
        await cloudinary.destroy(public_id)
        raise
    return _response(item)


@router.patch("/{item_id}", response_model=ClothingItemUploadResponse)
async def update_item(
    item_id: UUID,
    payload: ClothingItemUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> ClothingItemUploadResponse:
    item = await session.scalar(
        select(ClothingItem).where(
            ClothingItem.id == item_id,
            ClothingItem.user_id == current_user.id,
            ClothingItem.deleted_at.is_(None),
        )
    )
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Wardrobe item not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    item.is_uniform = item.category == "Uniform"
    item.user_verified = True
    item.user_verified_at = datetime.now(timezone.utc)
    await session.commit()
    await session.refresh(item)
    return _response(item)
