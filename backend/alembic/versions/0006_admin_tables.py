"""관리자 테이블 — admin_users + admin_actions

Revision ID: 0006
Revises: 0005
Create Date: 2026-06-20
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.engine.reflection import Inspector

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = Inspector.from_engine(conn)
    existing_tables = inspector.get_table_names()

    if "admin_users" not in existing_tables:
        op.create_table(
            "admin_users",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("username", sa.String(50), nullable=False, unique=True),
            sa.Column("hashed_password", sa.String(200), nullable=False),
            sa.Column("role", sa.String(20), nullable=False, server_default="moderator"),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        )

    if "admin_actions" not in existing_tables:
        op.create_table(
            "admin_actions",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("admin_id", sa.Integer(), sa.ForeignKey("admin_users.id"), nullable=False),
            sa.Column("action_type", sa.String(50), nullable=False),
            sa.Column("target_type", sa.String(20), nullable=True),
            sa.Column("target_id", sa.Integer(), nullable=True),
            sa.Column("detail", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    op.drop_table("admin_actions")
    op.drop_table("admin_users")
