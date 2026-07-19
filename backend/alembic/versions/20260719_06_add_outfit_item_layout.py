"""persist outfit canvas layouts

Revision ID: 20260719_06
Revises: 20260719_05
Create Date: 2026-07-19
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "20260719_06"
down_revision: Union[str, Sequence[str], None] = "20260719_05"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "outfits",
        sa.Column(
            "item_layout",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )
    op.alter_column("outfits", "item_layout", server_default=None)


def downgrade() -> None:
    op.drop_column("outfits", "item_layout")
