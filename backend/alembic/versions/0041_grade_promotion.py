"""매년 3/1 학년 자동 승급 — 중복 적용 방지용 연도 컬럼 추가

Revision ID: 0041
Revises: 0040
Create Date: 2026-07-14
"""
from alembic import op
import sqlalchemy as sa

revision = "0041"
down_revision = "0040"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("grade_promoted_year", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "grade_promoted_year")
