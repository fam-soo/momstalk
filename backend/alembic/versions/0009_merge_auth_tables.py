"""merge auth tables into single db

Revision ID: 0009
Revises: 0008
Create Date: 2026-06-27
"""
from alembic import op
import sqlalchemy as sa

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "phone_verifications",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("phone_number", sa.String(20), nullable=False, index=True),
        sa.Column("code", sa.String(6), nullable=False),
        sa.Column("is_used", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("NOW()"), nullable=False),
    )
    op.create_index("ix_phone_verifications_phone_number", "phone_verifications", ["phone_number"])

    op.create_table(
        "parent_verifications",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("anon_id", sa.String(64), nullable=False, unique=True),
        sa.Column("school_code", sa.String(20), nullable=False),
        sa.Column("school_name", sa.String(100), nullable=False),
        sa.Column("grade", sa.Integer(), nullable=False),
        sa.Column("class_num", sa.Integer(), nullable=False),
        sa.Column("school_type", sa.String(10), nullable=False),
        sa.Column("verified_at", sa.DateTime(), server_default=sa.text("NOW()"), nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default="true", nullable=False),
    )
    op.create_index("ix_parent_verifications_anon_id", "parent_verifications", ["anon_id"])


def downgrade() -> None:
    op.drop_table("parent_verifications")
    op.drop_table("phone_verifications")
