import asyncio

from fastapi import APIRouter, Depends, HTTPException, status
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.models.user import User
from app.schemas.auth import GoogleAuthRequest, TokenResponse, UserResponse

router = APIRouter()


@router.post("/google", response_model=TokenResponse)
async def google_login(payload: GoogleAuthRequest, session: AsyncSession = Depends(get_db_session)) -> TokenResponse:
    settings = get_settings()
    if not settings.google_oauth_web_client_id:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Google sign-in is not configured")

    try:
        claims = await asyncio.to_thread(
            google_id_token.verify_oauth2_token,
            payload.id_token,
            google_requests.Request(),
            settings.google_oauth_web_client_id,
        )
    except ValueError as error:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Google ID token") from error

    email = claims.get("email")
    email_verified = claims.get("email_verified")
    subject = claims.get("sub")
    if not isinstance(email, str) or not email or email_verified is not True or not isinstance(subject, str) or not subject:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Google account email is not verified")

    email = email.casefold()
    user = await session.scalar(select(User).where(User.email == email))
    if user is None:
        display_name = claims.get("name")
        user = User(email=email, display_name=display_name.strip() if isinstance(display_name, str) else None)
        session.add(user)
        await session.commit()
        await session.refresh(user)
    return TokenResponse(access_token=create_access_token(str(user.id)), user=UserResponse.model_validate(user))


@router.get("/me", response_model=UserResponse)
async def me(current_user: User = Depends(get_current_user)) -> UserResponse:
    return UserResponse.model_validate(current_user)
