"""add schools table for NEIS cache

Revision ID: 0012
Revises: 0011
Create Date: 2026-06-28
"""
import sqlalchemy as sa
from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "schools",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("school_code", sa.String(20), unique=True, nullable=False),
        sa.Column("school_name", sa.String(100), nullable=False),
        sa.Column("school_type", sa.String(10), nullable=False),
        sa.Column("address", sa.String(200), nullable=True),
        sa.Column("region", sa.String(50), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
    )
    op.create_index("ix_schools_school_code", "schools", ["school_code"])
    op.create_index("ix_schools_school_name", "schools", ["school_name"])
    op.create_index("ix_schools_region", "schools", ["region"])


def downgrade() -> None:
    op.drop_table("schools")
