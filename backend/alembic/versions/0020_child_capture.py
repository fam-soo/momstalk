"""auth_captures: unique 제거, capture_type 추가 (자녀 추가 인증 지원)

Revision ID: 0020
Revises: 0019
Create Date: 2026-07-04
"""
from alembic import op
import sqlalchemy as sa

revision = "0020"
down_revision = "0019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # unique 제약 제거 (사용자당 여러 자녀 캡처 허용)
    op.drop_constraint("auth_captures_user_id_key", "auth_captures", type_="unique")
    # capture_type 컬럼 추가 (initial: 최초 가입, child_add: 자녀 추가)
    op.add_column("auth_captures", sa.Column("capture_type", sa.String(20), server_default="initial", nullable=False))
    # 복합 인덱스 (user_id + capture_type)로 빠른 조회
    op.create_index("ix_auth_captures_user_id_type", "auth_captures", ["user_id", "capture_type"])


def downgrade() -> None:
    op.drop_index("ix_auth_captures_user_id_type", table_name="auth_captures")
    op.drop_column("auth_captures", "capture_type")
    op.create_unique_constraint("auth_captures_user_id_key", "auth_captures", ["user_id"])
