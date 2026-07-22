from fastapi import APIRouter, Depends, Header, HTTPException, status # type: ignore
from sqlalchemy.ext.asyncio import AsyncSession # type: ignore

from app.api.deps import get_db_session
from app.core.config import get_settings
from app.services.cloudinary_reconciler import reconcile_cloudinary_deletions

router = APIRouter()


@router.get("/reconcile/cloudinary")
async def reconcile_cloudinary(
    authorization: str | None = Header(default=None),
    session: AsyncSession = Depends(get_db_session),
) -> dict[str, int]:
    secret = get_settings().cron_secret
    if not secret or authorization != f"Bearer {secret}":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    completed = await reconcile_cloudinary_deletions(session)
    return {"completed": completed}
