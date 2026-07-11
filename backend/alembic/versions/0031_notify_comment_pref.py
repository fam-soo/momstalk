"""notification_prefs.notify_comment 추가 — 내 글 댓글 알림 개별 on/off

기존엔 댓글 알림이 항상 발송됐다. 이제 다른 알림(게시판 새 글)처럼
사용자가 직접 켜고 끌 수 있게 한다. 기존 동작을 바꾸지 않도록
default=True(opt-out)로 추가한다.

Revision ID: 0031
Revises: 0030
Create Date: 2026-07-12
"""
from alembic import op
import sqlalchemy as sa

revision = "0031"
down_revision = "0030"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "notification_prefs",
        sa.Column("notify_comment", sa.Boolean, nullable=False, server_default=sa.true()),
    )


def downgrade() -> None:
    op.drop_column("notification_prefs", "notify_comment")
