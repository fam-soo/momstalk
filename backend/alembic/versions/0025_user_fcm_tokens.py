"""user_fcm_tokens: 기기별 다중 FCM 토큰 지원

users.fcm_token은 단일 컬럼이라 같은 계정을 여러 기기(모바일+PC 웹 등)에서
동시에 쓰면 나중에 등록한 기기의 토큰만 남고 이전 토큰은 덮어써져,
동시에 켜둔 다른 기기는 알림을 받지 못했다. 기기별 토큰을 별도 테이블에
저장해 모든 등록된 기기로 발송할 수 있도록 한다.

Revision ID: 0025
Revises: 0024
Create Date: 2026-07-07
"""
from alembic import op
import sqlalchemy as sa

revision = "0025"
down_revision = "0024"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_fcm_tokens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token", sa.String(300), nullable=False, unique=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
    )
    op.create_index("ix_user_fcm_tokens_user_id", "user_fcm_tokens", ["user_id"])
    op.create_index("ix_user_fcm_tokens_token", "user_fcm_tokens", ["token"], unique=True)

    # 기존 단일 토큰(users.fcm_token)이 있으면 새 테이블로 이관
    conn = op.get_bind()
    conn.execute(sa.text(
        "INSERT INTO user_fcm_tokens (user_id, token, created_at, updated_at) "
        "SELECT id, fcm_token, NOW(), NOW() FROM users "
        "WHERE fcm_token IS NOT NULL AND fcm_token <> '' "
        "ON CONFLICT (token) DO NOTHING"
    ))


def downgrade() -> None:
    op.drop_index("ix_user_fcm_tokens_token", table_name="user_fcm_tokens")
    op.drop_index("ix_user_fcm_tokens_user_id", table_name="user_fcm_tokens")
    op.drop_table("user_fcm_tokens")
