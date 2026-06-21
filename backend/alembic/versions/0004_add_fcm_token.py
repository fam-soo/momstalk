"""add fcm_token to users

Revision ID: 0004
Revises: 0003
Create Date: 2026-06-20
"""
from alembic import op
import sqlalchemy as sa

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade():
    from sqlalchemy import inspect
    bind = op.get_bind()
    existing_cols = {c["name"] for c in inspect(bind).get_columns("users")}
    if "fcm_token" not in existing_cols:
        op.add_column("users", sa.Column("fcm_token", sa.String(256), nullable=True))


def downgrade():
    op.drop_column("users", "fcm_token")
