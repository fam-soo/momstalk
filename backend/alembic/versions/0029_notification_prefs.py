"""notification_prefs 테이블 추가 — 게시판 종류별 새 글 알림 on/off

지역/학교/학년/학원 게시판에 새 글이 올라올 때 알림을 받을지 유저가
게시판 종류별로 직접 켜고 끌 수 있게 한다.

Revision ID: 0029
Revises: 0028
Create Date: 2026-07-10
"""
from alembic import op
import sqlalchemy as sa

revision = "0029"
down_revision = "0028"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "notification_prefs",
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("notify_region", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("notify_school", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("notify_grade", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("notify_academy", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("updated_at", sa.DateTime, server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("notification_prefs")
