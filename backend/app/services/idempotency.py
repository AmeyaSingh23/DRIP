from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.idempotency_record import IdempotencyRecord

_PENDING_LEASE = timedelta(minutes=3)


@dataclass(frozen=True)
class IdempotencyLease:
    record: IdempotencyRecord
    completed_resource_id: UUID | None = None


def _validate_key(value: str | None) -> str:
    if value is None or not value or len(value) > 64:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A valid Idempotency-Key header is required",
        )
    if not all(character.isascii() and (character.isalnum() or character in "-_") for character in value):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Idempotency-Key contains unsupported characters",
        )
    return value


async def acquire_idempotency_lease(
    session: AsyncSession,
    *,
    user_id: UUID,
    operation: str,
    key: str | None,
) -> IdempotencyLease:
    key = _validate_key(key)
    record = await session.scalar(
        select(IdempotencyRecord).where(
            IdempotencyRecord.user_id == user_id,
            IdempotencyRecord.operation == operation,
            IdempotencyRecord.key == key,
        )
    )
    if record is None:
        record = IdempotencyRecord(user_id=user_id, operation=operation, key=key)
        session.add(record)
        try:
            await session.commit()
            await session.refresh(record)
            return IdempotencyLease(record)
        except IntegrityError:
            await session.rollback()
            record = await session.scalar(
                select(IdempotencyRecord).where(
                    IdempotencyRecord.user_id == user_id,
                    IdempotencyRecord.operation == operation,
                    IdempotencyRecord.key == key,
                )
            )
            if record is None:
                raise

    if record.status == "completed" and record.resource_id is not None:
        return IdempotencyLease(record, completed_resource_id=record.resource_id)

    now = datetime.now(timezone.utc)
    updated_at = record.updated_at if record.updated_at.tzinfo else record.updated_at.replace(tzinfo=timezone.utc)
    if now - updated_at < _PENDING_LEASE:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This request is still being processed. Please wait before retrying.",
            headers={"Retry-After": "15"},
        )

    record.status = "pending"
    record.updated_at = now
    await session.commit()
    return IdempotencyLease(record)


async def complete_idempotency_lease(
    session: AsyncSession,
    lease: IdempotencyLease,
    resource_id: UUID,
) -> None:
    lease.record.status = "completed"
    lease.record.resource_id = resource_id
    lease.record.updated_at = datetime.now(timezone.utc)
    await session.commit()
