"""add suspension fields, report categories, user_warnings table

Revision ID: 0003
Revises: 0002
Create Date: 2026-06-20
"""
from alembic import op
import sqlalchemy as sa

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    from sqlalchemy import inspect, text
    inspector = inspect(bind)
    existing_tables = inspector.get_table_names()
    existing_cols = {c["name"] for c in inspector.get_columns("users")}

    # users 테이블: suspended_until, warning_count 추가
    if "suspended_until" not in existing_cols:
        op.add_column("users", sa.Column("suspended_until", sa.DateTime(), nullable=True))
    if "warning_count" not in existing_cols:
        op.add_column("users", sa.Column("warning_count", sa.Integer(), nullable=True, server_default="0"))

    # reports 테이블: category, status, reviewed_by, reviewed_at, action_taken 추가
    if "reports" in existing_tables:
        report_cols = {c["name"] for c in inspector.get_columns("reports")}
        if "category" not in report_cols:
            op.add_column("reports", sa.Column("category", sa.String(20), nullable=True, server_default="OTHER"))
        if "status" not in report_cols:
            op.add_column("reports", sa.Column("status", sa.String(20), nullable=True, server_default="pending"))
        if "reviewed_by" not in report_cols:
            op.add_column("reports", sa.Column("reviewed_by", sa.Integer(), nullable=True))
        if "reviewed_at" not in report_cols:
            op.add_column("reports", sa.Column("reviewed_at", sa.DateTime(), nullable=True))
        if "action_taken" not in report_cols:
            op.add_column("reports", sa.Column("action_taken", sa.String(50), nullable=True))

    # user_warnings 테이블 신규 생성
    if "user_warnings" not in existing_tables:
        op.create_table(
            "user_warnings",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("reason", sa.Text(), nullable=False),
            sa.Column("warning_type", sa.String(20), nullable=False),
            sa.Column("issued_by", sa.Integer(), nullable=True),
            sa.Column("expires_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        )
        op.create_index("ix_user_warnings_user_id", "user_warnings", ["user_id"])


def downgrade():
    op.drop_table("user_warnings")
    for col in ("action_taken", "reviewed_at", "reviewed_by", "status", "category"):
        op.drop_column("reports", col)
    op.drop_column("users", "warning_count")
    op.drop_column("users", "suspended_until")
