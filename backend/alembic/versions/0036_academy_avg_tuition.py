"""academies.avg_tuition_10k_won 추가 — 학원비 평균(만원) 표시용

Revision ID: 0036
Revises: 0035
Create Date: 2026-07-14
"""
from alembic import op
import sqlalchemy as sa

revision = "0036"
down_revision = "0035"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("academies", sa.Column("avg_tuition_10k_won", sa.Numeric(6, 1), nullable=True))


def downgrade() -> None:
    op.drop_column("academies", "avg_tuition_10k_won")
