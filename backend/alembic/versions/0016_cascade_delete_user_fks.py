"""cascade delete on user foreign keys

Revision ID: 0016
Revises: 0015
Create Date: 2026-06-29
"""
from alembic import op

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None


# (table, fk_name, column, ondelete)
_CASCADE_FKS = [
    ("auth_captures",   "auth_captures_user_id_fkey",      "user_id"),
    ("likes",           "likes_user_id_fkey",               "user_id"),
    ("scraps",          "scraps_user_id_fkey",              "user_id"),
    ("reports",         "reports_reporter_id_fkey",         "reporter_id"),
    ("user_warnings",   "user_warnings_user_id_fkey",       "user_id"),
    ("blocks",          "blocks_user_id_fkey",              "user_id"),
    ("direct_messages", "direct_messages_sender_id_fkey",   "sender_id"),
    ("conversations",   "conversations_user_a_id_fkey",     "user_a_id"),
    ("conversations",   "conversations_user_b_id_fkey",     "user_b_id"),
    ("comments",        "comments_author_id_fkey",          "author_id"),
    ("posts",           "posts_author_id_fkey",             "author_id"),
]

# admin_actions.admin_id: 감사 로그 보존을 위해 SET NULL (nullable로 변경)
_SET_NULL_FK = ("admin_actions", "admin_actions_admin_id_fkey", "admin_id")


def upgrade():
    # CASCADE: 유저 삭제 시 관련 레코드 자동 삭제
    for table, fk_name, col in _CASCADE_FKS:
        op.drop_constraint(fk_name, table, type_="foreignkey")
        op.create_foreign_key(fk_name, table, "users", [col], ["id"], ondelete="CASCADE")

    # admin_actions: nullable로 변경 후 SET NULL
    table, fk_name, col = _SET_NULL_FK
    op.drop_constraint(fk_name, table, type_="foreignkey")
    op.alter_column(table, col, nullable=True)
    op.create_foreign_key(fk_name, table, "users", [col], ["id"], ondelete="SET NULL")


def downgrade():
    for table, fk_name, col in _CASCADE_FKS:
        op.drop_constraint(fk_name, table, type_="foreignkey")
        op.create_foreign_key(fk_name, table, "users", [col], ["id"])

    table, fk_name, col = _SET_NULL_FK
    op.drop_constraint(fk_name, table, type_="foreignkey")
    op.alter_column(table, col, nullable=False)
    op.create_foreign_key(fk_name, table, "users", [col], ["id"])
