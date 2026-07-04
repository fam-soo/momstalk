"""users: kakao_id, is_trusted 컬럼 추가

kakao_id: 관리자 사용자 조회 시 카카오 계정 식별자 표시용
is_trusted: 자녀 추가·인증 캡처 심사 면제 권한

Revision ID: 0021
Revises: 0020
Create Date: 2026-07-04
"""
from alembic import op
import sqlalchemy as sa

revision = "0021"
down_revision = "0020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("kakao_id", sa.String(30), nullable=True))
    op.add_column("users", sa.Column("is_trusted", sa.Boolean, server_default="false", nullable=False))
    op.create_index("ix_users_kakao_id", "users", ["kakao_id"])


def downgrade() -> None:
    op.drop_index("ix_users_kakao_id", table_name="users")
    op.drop_column("users", "is_trusted")
    op.drop_column("users", "kakao_id")
