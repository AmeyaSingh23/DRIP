from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool # type: ignore

from app.core.config import get_settings
from app.db.base import Base
from app.db.models import CalendarEntry, CloudinaryDeletionJob, ClothingItem, IdempotencyRecord, Outfit, OutfitItem, User  # noqa: F401

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

settings = get_settings()
if not settings.database_url_migrations:
    raise RuntimeError("DATABASE_URL_MIGRATIONS must be set to Neon's direct connection string before running Alembic.")

migration_url = settings.database_url_migrations
config.set_main_option("sqlalchemy.url", migration_url)
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=migration_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
    connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
