from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from io import BytesIO
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Query, Response, UploadFile, status
from PIL import Image, UnidentifiedImageError
from sqlalchemy import String, cast, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.db.models.cloudinary_deletion_job import CloudinaryDeletionJob
from app.db.models.calendar_entry import CalendarEntry
from app.db.models.clothing_item import ClothingItem
from app.db.models.outfit import Outfit, OutfitItem
from app.db.models.user import User
from app.schemas.clothing_item import (
    CalendarUsage,
    ClothingItemTags,
    ClothingItemUpdate,
    ClothingItemUploadResponse,
    ClothingItemUsageResponse,
    OutfitUsage,
)
from app.services.cloudinary_service import CloudinaryService
from app.services.cloudinary_reconciler import reconcile_cloudinary_deletions
from app.services.gemini_tagger import GeminiTagger
from app.services.idempotency import acquire_idempotency_lease, complete_idempotency_lease

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
        is_clothing_item=True,
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


async def _active_item_or_404(item_id: UUID, user_id: UUID, session: AsyncSession) -> ClothingItem:
    item = await session.scalar(
        select(ClothingItem).where(
            ClothingItem.id == item_id,
            ClothingItem.user_id == user_id,
            ClothingItem.deleted_at.is_(None),
        )
    )
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Wardrobe item not found")
    return item


@router.get("", response_model=list[ClothingItemUploadResponse])
async def list_items(
    category: str | None = Query(default=None, max_length=50),
    search: str | None = Query(default=None, max_length=100),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> list[ClothingItemUploadResponse]:
    statement = select(ClothingItem).where(
        ClothingItem.user_id == current_user.id,
        ClothingItem.deleted_at.is_(None),
    )
    if category and category != "All":
        statement = statement.where(ClothingItem.category == category)
    if search and (term := search.strip()):
        pattern = f"%{term}%"
        statement = statement.where(
            or_(
                ClothingItem.item_name.ilike(pattern),
                ClothingItem.category.ilike(pattern),
                ClothingItem.custom_category.ilike(pattern),
                ClothingItem.color.ilike(pattern),
                ClothingItem.pattern.ilike(pattern),
                ClothingItem.fabric.ilike(pattern),
                cast(ClothingItem.tags, String).ilike(pattern),
            )
        )
    items = (await session.scalars(statement.order_by(ClothingItem.created_at.desc()))).all()
    return [_response(item) for item in items]


@router.get("/{item_id}", response_model=ClothingItemUploadResponse)
async def get_item(
    item_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> ClothingItemUploadResponse:
    return _response(await _active_item_or_404(item_id, current_user.id, session))


@router.get("/{item_id}/usage", response_model=ClothingItemUsageResponse)
async def get_item_usage(
    item_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> ClothingItemUsageResponse:
    item = await _active_item_or_404(item_id, current_user.id, session)
    outfit_rows = (
        await session.execute(
            select(Outfit.id, Outfit.name)
            .join(OutfitItem, OutfitItem.outfit_id == Outfit.id)
            .where(
                OutfitItem.clothing_item_id == item.id,
                Outfit.user_id == current_user.id,
            )
            .order_by(Outfit.created_at.desc())
        )
    ).all()
    outfit_ids = [outfit_id for outfit_id, _ in outfit_rows]
    calendar_rows = []
    if outfit_ids:
        calendar_rows = (
            await session.execute(
                select(CalendarEntry.entry_date, CalendarEntry.slot, Outfit.id, Outfit.name)
                .join(Outfit, CalendarEntry.outfit_id == Outfit.id)
                .where(
                    CalendarEntry.user_id == current_user.id,
                    CalendarEntry.outfit_id.in_(outfit_ids),
                )
                .order_by(CalendarEntry.entry_date.desc())
                .limit(20)
            )
        ).all()
    return ClothingItemUsageResponse(
        outfit_count=len(outfit_rows),
        outfits=[OutfitUsage(outfit_id=outfit_id, outfit_name=name) for outfit_id, name in outfit_rows],
        calendar_history=[
            CalendarUsage(
                entry_date=entry_date,
                slot=slot,
                outfit_id=outfit_id,
                outfit_name=outfit_name,
            )
            for entry_date, slot, outfit_id, outfit_name in calendar_rows
        ],
    )


@router.post("/tag", response_model=ClothingItemTags)
async def tag_item(
    tagging_image: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
) -> ClothingItemTags:
    tagging_bytes = await tagging_image.read()
    tagging_type = _validate_image(tagging_bytes, tagging_image.content_type, 4 * 1024 * 1024, "Tagging image")
    tags = await GeminiTagger().tag(tagging_bytes, tagging_type)
    if not tags.is_clothing_item:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No clothing item was detected. Photograph one garment on a contrasting background and try again.",
        )
    return tags


@router.post("/manual", response_model=ClothingItemUploadResponse, status_code=status.HTTP_201_CREATED)
async def upload_item_manually(
    cutout: UploadFile = File(...),
    category: str = Form(...),
    item_name: str | None = Form(default=None),
    color: str | None = Form(default=None),
    custom_category: str | None = Form(default=None),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> ClothingItemUploadResponse:
    cutout_bytes = await cutout.read()
    if _validate_image(cutout_bytes, cutout.content_type, 20 * 1024 * 1024, "Cutout") != "image/png":
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Cutout must be a transparent PNG")
    lease = await acquire_idempotency_lease(
        session,
        user_id=current_user.id,
        operation="wardrobe_upload",
        key=idempotency_key,
    )
    if lease.completed_resource_id is not None:
        item = await session.scalar(
            select(ClothingItem).where(
                ClothingItem.id == lease.completed_resource_id,
                ClothingItem.user_id == current_user.id,
            )
        )
        if item is None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This upload is no longer available. Start a new upload.")
        return _response(item)
    cloudinary_url, public_id = await CloudinaryService().upload_cutout(
        cutout_bytes,
        current_user.id,
        idempotency_key=lease.record.key,
    )
    item = ClothingItem(
        user_id=current_user.id, cloudinary_url=cloudinary_url, cloudinary_public_id=public_id,
        category=category.strip()[:50] or "Custom", custom_category=custom_category.strip()[:100] if custom_category else None,
        color=color.strip()[:50] if color else None, item_name=item_name.strip()[:120] if item_name else None,
        is_uniform=category == "Uniform", tags=[], ai_confidence=0, user_verified=True,
        user_verified_at=datetime.now(timezone.utc),
    )
    try:
        session.add(item)
        await session.flush()
        await complete_idempotency_lease(session, lease, item.id)
        await session.refresh(item)
    except Exception:
        await session.rollback()
        raise
    return _response(item)


@router.patch("/{item_id}", response_model=ClothingItemUploadResponse)
async def update_item(
    item_id: UUID,
    payload: ClothingItemUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> ClothingItemUploadResponse:
    item = await _active_item_or_404(item_id, current_user.id, session)
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    item.is_uniform = item.category == "Uniform"
    item.user_verified = True
    item.user_verified_at = datetime.now(timezone.utc)
    await session.commit()
    await session.refresh(item)
    return _response(item)


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def soft_delete_item(
    item_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> Response:
    item = await _active_item_or_404(item_id, current_user.id, session)
    item.deleted_at = datetime.now(timezone.utc)
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/{item_id}/permanent", status_code=status.HTTP_204_NO_CONTENT)
async def permanently_erase_item(
    item_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> Response:
    item = await _active_item_or_404(item_id, current_user.id, session)
    referenced_by_outfit = await session.scalar(
        select(OutfitItem.id).where(OutfitItem.clothing_item_id == item.id).limit(1)
    )
    if referenced_by_outfit is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This item is used in a saved outfit. Remove it from the outfit first, or use Remove from wardrobe to preserve history.",
        )
    session.add(
        CloudinaryDeletionJob(
            user_id=current_user.id,
            public_id=item.cloudinary_public_id,
        )
    )
    await session.delete(item)
    await session.commit()
    await reconcile_cloudinary_deletions(session, limit=1)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
