from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.cloudinary_deletion_job import CloudinaryDeletionJob
from app.services.cloudinary_service import CloudinaryService


async def reconcile_cloudinary_deletions(session: AsyncSession, *, limit: int = 25) -> int:
    jobs = (
        await session.scalars(
            select(CloudinaryDeletionJob)
            .where(CloudinaryDeletionJob.status.in_(("pending", "failed")))
            .order_by(CloudinaryDeletionJob.created_at)
            .limit(limit)
        )
    ).all()
    completed = 0
    try:
        cloudinary = CloudinaryService()
    except Exception as error:
        for job in jobs:
            job.attempts += 1
            job.status = "failed"
            job.last_error = str(error)[:1000]
        if jobs:
            await session.commit()
        return 0
    for job in jobs:
        job.attempts += 1
        try:
            await cloudinary.destroy(job.public_id)
        except Exception as error:
            job.status = "failed"
            job.last_error = str(error)[:1000]
        else:
            job.status = "completed"
            job.last_error = None
            job.completed_at = datetime.now(timezone.utc)
            completed += 1
        await session.commit()
    return completed
