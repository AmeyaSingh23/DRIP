from collections.abc import AsyncGenerator
from uuid import UUID

import jwt # type: ignore
from fastapi import Depends, HTTPException, status # type: ignore
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer # type: ignore
from sqlalchemy import select # type: ignore
from sqlalchemy.ext.asyncio import AsyncSession # type: ignore

from app.core.config import get_settings
from app.db.models.user import User
from app.db.session import async_session_factory

bearer_scheme = HTTPBearer(auto_error=False)


import logging

logger = logging.getLogger(__name__)

async def get_db_session() -> AsyncGenerator[AsyncSession, None]:
    session = async_session_factory()
    try:
        yield session
    finally:
        try:
            await session.close()
        except Exception as e:
            logger.warning("Failed to close database session cleanly: %s", e)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    session: AsyncSession = Depends(get_db_session),
) -> User:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired access token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise unauthorized

    settings = get_settings()
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
            audience=settings.jwt_audience,
            issuer=settings.jwt_issuer,
        )
        user_id = UUID(str(payload["sub"]))
        session_version = int(payload["sv"])
    except (jwt.InvalidTokenError, KeyError, ValueError):
        raise unauthorized

    user = await session.scalar(select(User).where(User.id == user_id))
    if user is None or user.session_version != session_version:
        raise unauthorized
    return user
