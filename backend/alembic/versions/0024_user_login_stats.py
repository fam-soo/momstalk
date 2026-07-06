"""users: last_login_at, login_count 추가 (관리자 화면 접속 통계용)

Revision ID: 0024
Revises: 0023
Create Date: 2026-07-06
"""
from alembic import op
import sqlalchemy as sa

revision = "0024"
down_revision = "0023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("last_login_at", sa.DateTime(), nullable=True))
    op.add_column("users", sa.Column("login_count", sa.Integer(), server_default="0", nullable=False))


def downgrade() -> None:
    op.drop_column("users", "login_count")
    op.drop_column("users", "last_login_at")
