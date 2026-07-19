from __future__ import annotations

import asyncio
from uuid import UUID

import cloudinary
import cloudinary.uploader
from fastapi import HTTPException, status

from app.core.config import get_settings


class CloudinaryService:
    def __init__(self) -> None:
        settings = get_settings()
        if not all((settings.cloudinary_cloud_name, settings.cloudinary_api_key, settings.cloudinary_api_secret)):
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Cloudinary is not configured on the server")
        cloudinary.config(
            cloud_name=settings.cloudinary_cloud_name,
            api_key=settings.cloudinary_api_key,
            api_secret=settings.cloudinary_api_secret,
            secure=True,
        )

    async def upload_cutout(
        self,
        image_bytes: bytes,
        user_id: UUID,
        *,
        idempotency_key: str,
    ) -> tuple[str, str]:
        result = await asyncio.to_thread(
            cloudinary.uploader.upload,
            image_bytes,
            folder=f"la-maison-de-miniso/{user_id}",
            public_id=f"item_{idempotency_key}",
            resource_type="image",
            format="png",
            overwrite=True,
            unique_filename=False,
            invalidate=True,
        )
        return str(result["secure_url"]), str(result["public_id"])

    async def destroy(self, public_id: str) -> None:
        await asyncio.to_thread(cloudinary.uploader.destroy, public_id, resource_type="image", invalidate=True)
