"""academies.facilities 추가 — 오늘학교 "시설 및 편의사항"(자습실/설명회/스터디모임)

Revision ID: 0037
Revises: 0036
Create Date: 2026-07-13
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = "0037"
down_revision = "0036"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("academies", sa.Column("facilities", JSONB, nullable=True))


def downgrade() -> None:
    op.drop_column("academies", "facilities")
