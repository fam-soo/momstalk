"""admin_actions.admin_id FK: admin_users → users

Revision ID: 0011
Revises: 0010
Create Date: 2026-06-28
"""
from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 기존 FK 제거
    op.drop_constraint("admin_actions_admin_id_fkey", "admin_actions", type_="foreignkey")
    # users 테이블을 참조하도록 새 FK 추가
    op.create_foreign_key(
        "admin_actions_admin_id_fkey",
        "admin_actions",
        "users",
        ["admin_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("admin_actions_admin_id_fkey", "admin_actions", type_="foreignkey")
    op.create_foreign_key(
        "admin_actions_admin_id_fkey",
        "admin_actions",
        "admin_users",
        ["admin_id"],
        ["id"],
    )
