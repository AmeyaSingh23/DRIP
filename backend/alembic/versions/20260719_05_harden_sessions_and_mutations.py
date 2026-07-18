"""harden sessions and mutations

Revision ID: 20260719_05
Revises: 20260718_04
Create Date: 2026-07-19
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "20260719_05"
down_revision: Union[str, Sequence[str], None] = "20260718_04"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("session_version", sa.Integer(), nullable=False, server_default=sa.text("0")),
    )
    op.create_table(
        "idempotency_records",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("operation", sa.String(length=32), nullable=False),
        sa.Column("key", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
        sa.Column("resource_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "operation", "key", name="uq_idempotency_records_user_operation_key"),
    )
    op.create_index("ix_idempotency_records_user_status", "idempotency_records", ["user_id", "status"])
    op.create_table(
        "cloudinary_deletion_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("public_id", sa.String(length=255), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("public_id"),
    )
    op.create_index("ix_cloudinary_deletion_jobs_status_created", "cloudinary_deletion_jobs", ["status", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_cloudinary_deletion_jobs_status_created", table_name="cloudinary_deletion_jobs")
    op.drop_table("cloudinary_deletion_jobs")
    op.drop_index("ix_idempotency_records_user_status", table_name="idempotency_records")
    op.drop_table("idempotency_records")
    op.drop_column("users", "session_version")
