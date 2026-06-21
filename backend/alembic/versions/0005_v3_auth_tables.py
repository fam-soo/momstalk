"""v3 인증 — users 컬럼 추가 + auth_captures + invite_links

Revision ID: 0005
Revises: 0004
Create Date: 2026-06-20
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.engine.reflection import Inspector

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = Inspector.from_engine(conn)
    existing_cols = {c["name"] for c in inspector.get_columns("users")}

    for col_name, col_def in [
        ("social_provider", sa.Column("social_provider", sa.String(20), nullable=True)),
        ("member_grade", sa.Column("member_grade", sa.String(10), nullable=False, server_default="lurker")),
        ("auth_route", sa.Column("auth_route", sa.String(10), nullable=True)),
        ("auth_pending", sa.Column("auth_pending", sa.Boolean(), nullable=True, server_default="false")),
    ]:
        if col_name not in existing_cols:
            op.add_column("users", col_def)

    existing_tables = inspector.get_table_names()

    if "auth_captures" not in existing_tables:
        op.create_table(
            "auth_captures",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False, unique=True),
            sa.Column("s3_key", sa.String(300), nullable=False),
            sa.Column("input_school_code", sa.String(20), nullable=False),
            sa.Column("input_school_name", sa.String(100), nullable=False),
            sa.Column("input_grade", sa.Integer(), nullable=False),
            sa.Column("input_class_num", sa.Integer(), nullable=True),
            sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
            sa.Column("reviewed_by", sa.Integer(), nullable=True),
            sa.Column("reviewed_at", sa.DateTime(), nullable=True),
            sa.Column("reject_reason", sa.String(200), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        )

    if "invite_links" not in existing_tables:
        op.create_table(
            "invite_links",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("token", sa.String(64), nullable=False, unique=True, index=True),
            sa.Column("issuer_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("school_code", sa.String(20), nullable=False),
            sa.Column("school_name", sa.String(100), nullable=False),
            sa.Column("school_type", sa.String(10), nullable=False),
            sa.Column("used_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
            sa.Column("used_at", sa.DateTime(), nullable=True),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    op.drop_table("invite_links")
    op.drop_table("auth_captures")
    for col in ["auth_pending", "auth_route", "member_grade", "social_provider"]:
        op.drop_column("users", col)
