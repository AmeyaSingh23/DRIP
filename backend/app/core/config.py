from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "DRIP API"
    app_env: str = "development"
    database_url: str = Field(validation_alias="DATABASE_URL")
    database_url_migrations: str | None = Field(default=None, validation_alias="DATABASE_URL_MIGRATIONS")
    jwt_secret_key: str = Field(validation_alias="JWT_SECRET_KEY", min_length=32)
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = Field(default=60, ge=5, le=1440)
    jwt_issuer: str = "drip-api"
    jwt_audience: str = "drip-mobile"
    cors_origins: list[str] = Field(default_factory=list)
    google_oauth_web_client_id: str | None = Field(default=None, validation_alias="GOOGLE_OAUTH_WEB_CLIENT_ID")
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-3.5-flash"
    cloudinary_cloud_name: str | None = None
    cloudinary_api_key: str | None = None
    cloudinary_api_secret: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
