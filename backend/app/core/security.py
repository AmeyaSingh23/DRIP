from datetime import UTC, datetime, timedelta

import jwt

from app.core.config import get_settings

def create_access_token(subject: str, session_version: int) -> str:
    settings = get_settings()
    now = datetime.now(UTC)
    claims = {
        "sub": subject,
        "sv": session_version,
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": now,
        "exp": now + timedelta(minutes=settings.jwt_access_token_expire_minutes),
    }
    return jwt.encode(claims, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
