from __future__ import annotations

from datetime import date, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.db.models.calendar_entry import CalendarEntry
from app.db.models.outfit import Outfit
from app.db.models.user import User
from app.schemas.calendar_entry import CalendarEntryResponse, CalendarEntryUpsert

router = APIRouter()


def _response(entry: CalendarEntry, outfit_name: str | None = None) -> CalendarEntryResponse:
    return CalendarEntryResponse(
        id=entry.id,
        entry_date=entry.entry_date,
        slot=entry.slot,
        outfit_id=entry.outfit_id,
        outfit_name=outfit_name,
        notes=entry.notes,
        created_at=entry.created_at,
    )


async def _owned_outfit(outfit_id: UUID, user_id: UUID, session: AsyncSession) -> Outfit:
    outfit = await session.scalar(select(Outfit).where(Outfit.id == outfit_id, Outfit.user_id == user_id))
    if outfit is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Selected outfit is unavailable")
    return outfit


@router.get("", response_model=list[CalendarEntryResponse])
async def list_entries(
    start: date = Query(...),
    end: date = Query(...),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> list[CalendarEntryResponse]:
    if end < start or end - start > timedelta(days=93):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Choose a date range up to 93 days")
    rows = (
        await session.execute(
            select(CalendarEntry, Outfit.name)
            .outerjoin(Outfit, CalendarEntry.outfit_id == Outfit.id)
            .where(
                CalendarEntry.user_id == current_user.id,
                CalendarEntry.entry_date.between(start, end),
            )
            .order_by(CalendarEntry.entry_date, CalendarEntry.slot)
        )
    ).all()
    return [_response(entry, outfit_name) for entry, outfit_name in rows]


@router.put("", response_model=CalendarEntryResponse)
async def upsert_entry(
    payload: CalendarEntryUpsert,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> CalendarEntryResponse:
    outfit_name = None
    if payload.outfit_id is not None:
        outfit = await _owned_outfit(payload.outfit_id, current_user.id, session)
        outfit_name = outfit.name
    entry = await session.scalar(
        select(CalendarEntry).where(
            CalendarEntry.user_id == current_user.id,
            CalendarEntry.entry_date == payload.entry_date,
            CalendarEntry.slot == payload.slot,
        )
    )
    if entry is None:
        entry = CalendarEntry(user_id=current_user.id, **payload.model_dump())
        session.add(entry)
    else:
        entry.outfit_id = payload.outfit_id
        entry.notes = payload.notes
    await session.commit()
    await session.refresh(entry)
    return _response(entry, outfit_name)


@router.delete("/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_entry(
    entry_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> Response:
    entry = await session.scalar(
        select(CalendarEntry).where(CalendarEntry.id == entry_id, CalendarEntry.user_id == current_user.id)
    )
    if entry is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Calendar entry not found")
    await session.delete(entry)
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
