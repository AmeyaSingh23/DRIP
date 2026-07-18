from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.api.v1.routes.items import _response
from app.db.models.clothing_item import ClothingItem
from app.db.models.outfit import Outfit, OutfitItem
from app.db.models.user import User
from app.schemas.outfit import OutfitCreate, OutfitGenerateRequest, OutfitPreview, OutfitResponse
from app.services.gemini_outfit_generator import GeminiOutfitGenerator

router = APIRouter()


async def _active_items(
    item_ids: list[UUID], user_id: UUID, session: AsyncSession
) -> list[ClothingItem]:
    items = (
        await session.scalars(
            select(ClothingItem).where(
                ClothingItem.id.in_(item_ids),
                ClothingItem.user_id == user_id,
                ClothingItem.deleted_at.is_(None),
            )
        )
    ).all()
    if len(items) != len(item_ids):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="One or more selected wardrobe items are unavailable",
        )
    by_id = {item.id: item for item in items}
    return [by_id[item_id] for item_id in item_ids]


def _outfit_response(outfit: Outfit, items: list[ClothingItem]) -> OutfitResponse:
    return OutfitResponse(
        id=outfit.id,
        name=outfit.name,
        occasion=outfit.occasion,
        is_ai_generated=outfit.is_ai_generated,
        created_at=outfit.created_at,
        items=[_response(item) for item in items],
    )


async def _outfit_with_items(
    outfit_id: UUID, user_id: UUID, session: AsyncSession
) -> tuple[Outfit, list[ClothingItem]]:
    outfit = await session.scalar(
        select(Outfit).where(Outfit.id == outfit_id, Outfit.user_id == user_id)
    )
    if outfit is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Outfit not found")
    items = (
        await session.scalars(
            select(ClothingItem)
            .join(OutfitItem, OutfitItem.clothing_item_id == ClothingItem.id)
            .where(OutfitItem.outfit_id == outfit.id)
            .order_by(OutfitItem.display_order)
        )
    ).all()
    return outfit, items


@router.get("", response_model=list[OutfitResponse])
async def list_outfits(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> list[OutfitResponse]:
    outfits = (
        await session.scalars(
            select(Outfit)
            .where(Outfit.user_id == current_user.id)
            .order_by(Outfit.created_at.desc())
            .limit(100)
        )
    ).all()
    results = []
    for outfit in outfits:
        _, items = await _outfit_with_items(outfit.id, current_user.id, session)
        results.append(_outfit_response(outfit, items))
    return results


@router.get("/{outfit_id}", response_model=OutfitResponse)
async def get_outfit(
    outfit_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> OutfitResponse:
    outfit, items = await _outfit_with_items(outfit_id, current_user.id, session)
    return _outfit_response(outfit, items)


@router.post("/generate", response_model=OutfitPreview)
async def generate_outfit(
    payload: OutfitGenerateRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> OutfitPreview:
    items = (
        await session.scalars(
            select(ClothingItem).where(
                ClothingItem.user_id == current_user.id,
                ClothingItem.deleted_at.is_(None),
            )
        )
    ).all()
    if not items:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Add wardrobe items before generating an outfit",
        )
    suggestion = await GeminiOutfitGenerator().generate(
        items,
        occasion=payload.occasion,
        style_notes=payload.style_notes,
        weather_summary=payload.weather_summary,
    )
    allowed_ids = {item.id for item in items}
    item_ids = list(dict.fromkeys(suggestion.item_ids))
    if not item_ids or any(item_id not in allowed_ids for item_id in item_ids):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Gemini returned unavailable wardrobe items. Please try again.",
        )
    by_id = {item.id: item for item in items}
    return OutfitPreview(
        name=suggestion.name,
        occasion=payload.occasion,
        rationale=suggestion.rationale,
        item_ids=item_ids,
        items=[_response(by_id[item_id]) for item_id in item_ids],
    )


@router.post("", response_model=OutfitResponse, status_code=status.HTTP_201_CREATED)
async def save_outfit(
    payload: OutfitCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> OutfitResponse:
    items = await _active_items(payload.item_ids, current_user.id, session)
    outfit = Outfit(
        user_id=current_user.id,
        name=payload.name,
        occasion=payload.occasion,
        is_ai_generated=payload.is_ai_generated,
    )
    session.add(outfit)
    await session.flush()
    session.add_all(
        [
            OutfitItem(
                outfit_id=outfit.id,
                clothing_item_id=item_id,
                display_order=index,
            )
            for index, item_id in enumerate(payload.item_ids)
        ]
    )
    await session.commit()
    await session.refresh(outfit)
    return _outfit_response(outfit, items)
