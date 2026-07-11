"""초대 링크를 1회 소모성에서 정원제로 변경 (기본 24시간 · 최대 10명)

카카오톡 단체 채팅방 등에서 한 링크를 여러 명에게 동시에 공유하는
경우가 많아, 링크당 사용 인원 상한(max_uses)을 두고 그 안에서는 여러
명이 함께 쓸 수 있도록 바꾼다. 기존 발급 링크는 이미 사용된 것이든
아니든 새 정원제 기준(24시간/10명)의 영향을 받지 않도록 백필한다.

Revision ID: 0030
Revises: 0029
Create Date: 2026-07-11
"""
from alembic import op
import sqlalchemy as sa

revision = "0030"
down_revision = "0029"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("invite_links", sa.Column("max_uses", sa.Integer, nullable=False, server_default="10"))
    op.add_column("invite_links", sa.Column("use_count", sa.Integer, nullable=False, server_default="0"))

    # 기존에 이미 사용된(used_by IS NOT NULL) 링크는 use_count=1로 백필해
    # 남은 인원 계산이 어긋나지 않게 한다.
    op.execute("UPDATE invite_links SET use_count = 1 WHERE used_by IS NOT NULL")

    op.create_table(
        "invite_link_uses",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("invite_link_id", sa.Integer, sa.ForeignKey("invite_links.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("used_at", sa.DateTime, server_default=sa.func.now()),
        sa.UniqueConstraint("invite_link_id", "user_id", name="uq_invite_link_use"),
    )
    op.create_index("ix_invite_link_uses_invite_link_id", "invite_link_uses", ["invite_link_id"])

    # 기존에 이미 사용된 링크는 그 사용 이력을 새 테이블에도 백필
    op.execute("""
        INSERT INTO invite_link_uses (invite_link_id, user_id, used_at)
        SELECT id, used_by, COALESCE(used_at, NOW()) FROM invite_links WHERE used_by IS NOT NULL
    """)


def downgrade() -> None:
    op.drop_index("ix_invite_link_uses_invite_link_id", table_name="invite_link_uses")
    op.drop_table("invite_link_uses")
    op.drop_column("invite_links", "use_count")
    op.drop_column("invite_links", "max_uses")
