"""remove password hash from users

Revision ID: 20260718_04
Revises: 20260718_03
Create Date: 2026-07-18
"""

from alembic import op
import sqlalchemy as sa


revision = "20260718_04"
down_revision = "20260718_03"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_column("users", "password_hash")


def downgrade() -> None:
    op.add_column("users", sa.Column("password_hash", sa.String(length=255), nullable=True))
    op.execute("UPDATE users SET password_hash = 'oauth-only-account' WHERE password_hash IS NULL")
    op.alter_column("users", "password_hash", nullable=False)
