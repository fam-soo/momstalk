"""academy_reviews: is_hidden, is_seed, report_count server_default 추가

SQL로 직접 삽입 시 NULL이 들어가는 문제 방지.

Revision ID: 0018
Revises: 0017
Create Date: 2026-07-01
"""
import sqlalchemy as sa
from alembic import op

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None


def upgrade():
    op.alter_column("academy_reviews", "is_hidden",
                    existing_type=sa.Boolean(),
                    server_default="false",
                    existing_nullable=True)
    op.alter_column("academy_reviews", "is_seed",
                    existing_type=sa.Boolean(),
                    server_default="false",
                    existing_nullable=False)
    op.alter_column("academy_reviews", "report_count",
                    existing_type=sa.Integer(),
                    server_default="0",
                    existing_nullable=True)

    # 기존 NULL 값 → false/0/now() 으로 정리
    op.execute("UPDATE academy_reviews SET is_hidden = false WHERE is_hidden IS NULL")
    op.execute("UPDATE academy_reviews SET is_seed = false WHERE is_seed IS NULL")
    op.execute("UPDATE academy_reviews SET report_count = 0 WHERE report_count IS NULL")
    op.execute("UPDATE academy_reviews SET created_at = NOW() WHERE created_at IS NULL")


def downgrade():
    op.alter_column("academy_reviews", "is_hidden",
                    existing_type=sa.Boolean(),
                    server_default=None)
    op.alter_column("academy_reviews", "is_seed",
                    existing_type=sa.Boolean(),
                    server_default=None)
    op.alter_column("academy_reviews", "report_count",
                    existing_type=sa.Integer(),
                    server_default=None)
