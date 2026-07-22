from io import BytesIO
from PIL import Image  # type: ignore
import asyncio

import cloudinary  # type: ignore
import cloudinary.uploader  # type: ignore
import httpx  # type: ignore
from fastapi import HTTPException, status  # type: ignore

from app.core.config import get_settings

_RAPIDAPI_URL = "https://background-removal-ai.p.rapidapi.com/remove-background"
_RAPIDAPI_HOST = "background-removal-ai.p.rapidapi.com"


def trim_transparent_padding(image_bytes: bytes) -> bytes:
    try:
        with Image.open(BytesIO(image_bytes)) as img:
            img = img.convert("RGBA")
            bbox = img.getbbox()
            if bbox:
                left, upper, right, lower = bbox
                padding = 8
                left = max(0, left - padding)
                upper = max(0, upper - padding)
                right = min(img.width, right + padding)
                lower = min(img.height, lower + padding)
                cropped = img.crop((left, upper, right, lower))
                out = BytesIO()
                cropped.save(out, format="PNG")
                return out.getvalue()
    except Exception:
        pass
    return image_bytes


class BgRemovalService:
    def __init__(self) -> None:
        settings = get_settings()
        if not settings.rapidapi_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Background removal is not configured on the server",
            )
        if not all((settings.cloudinary_cloud_name, settings.cloudinary_api_key, settings.cloudinary_api_secret)):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Cloudinary is not configured on the server",
            )
        self._rapidapi_key = settings.rapidapi_key
        cloudinary.config(
            cloud_name=settings.cloudinary_cloud_name,
            api_key=settings.cloudinary_api_key,
            api_secret=settings.cloudinary_api_secret,
            secure=True,
        )

    async def _delete_temp_upload(self, public_id: str) -> None:
        for attempt in range(3):
            try:
                await asyncio.to_thread(
                    cloudinary.uploader.destroy,
                    public_id,
                    resource_type="image",
                    invalidate=True,
                )
                return
            except Exception:
                if attempt < 2:
                    await asyncio.sleep(2 ** attempt)

    async def remove_background(self, image_data: bytes, content_type: str) -> bytes:
        del content_type  # Cloudinary detects the image type from the bytes.
        public_id: str | None = None
        try:
            upload_result = await asyncio.to_thread(
                cloudinary.uploader.upload,
                image_data,
                folder="wardrobe_temp",
                resource_type="image",
            )
            public_id = str(upload_result["public_id"])
            source_url = upload_result.get("secure_url")
            if not isinstance(source_url, str) or not source_url:
                raise ValueError("Cloudinary did not return a source URL")

            timeout = httpx.Timeout(45.0, connect=10.0)
            headers = {
                "x-rapidapi-key": self._rapidapi_key,
                "x-rapidapi-host": _RAPIDAPI_HOST,
            }
            async with httpx.AsyncClient(timeout=timeout) as client:
                removal_response = await client.post(
                    _RAPIDAPI_URL,
                    json={"image_url": source_url},
                    headers=headers,
                )
                removal_response.raise_for_status()
                payload = removal_response.json()
                png_url = payload.get("image_url") if isinstance(payload, dict) else None
                if not isinstance(png_url, str) or not png_url:
                    raise ValueError("RapidAPI did not return a cutout URL")

                png_response = await client.get(png_url)
                png_response.raise_for_status()
                if not png_response.content:
                    raise ValueError("RapidAPI returned an empty cutout")
                return trim_transparent_padding(png_response.content)
        except HTTPException:
            raise
        except (httpx.HTTPError, ValueError, KeyError, TypeError) as error:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Background removal failed. Please try again.",
            ) from error
        finally:
            if public_id is not None:
                await self._delete_temp_upload(public_id)

