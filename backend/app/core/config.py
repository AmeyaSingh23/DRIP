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


@lru_cache
def get_settings() -> Settings:
    return Settings()
