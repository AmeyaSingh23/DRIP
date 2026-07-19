from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "La Maison de Miniso API"
    app_env: str = "development"
    database_url: str = Field(validation_alias="DATABASE_URL")
    database_url_migrations: str | None = Field(default=None, validation_alias="DATABASE_URL_MIGRATIONS")
    jwt_secret_key: str = Field(validation_alias="JWT_SECRET_KEY", min_length=32)
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = Field(default=43200, ge=5, le=43200)
    jwt_issuer: str = "la-maison-de-miniso-api"
    jwt_audience: str = "la-maison-de-miniso-mobile"
    cors_origins: list[str] = Field(default_factory=list)
    google_oauth_web_client_id: str | None = Field(default=None, validation_alias="GOOGLE_OAUTH_WEB_CLIENT_ID")
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-3.5-flash"
    rapidapi_key: str | None = Field(default=None, validation_alias="RAPIDAPI_KEY")
    cloudinary_cloud_name: str | None = None
    cloudinary_api_key: str | None = None
    cloudinary_api_secret: str | None = None
    cron_secret: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
