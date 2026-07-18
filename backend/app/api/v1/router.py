from fastapi import APIRouter

from app.api.v1.routes.auth import router as auth_router
from app.api.v1.routes.items import router as items_router
from app.api.v1.routes.outfits import router as outfits_router

api_router = APIRouter()
api_router.include_router(auth_router, prefix="/auth", tags=["auth"])
api_router.include_router(items_router, prefix="/items", tags=["items"])
api_router.include_router(outfits_router, prefix="/outfits", tags=["outfits"])
