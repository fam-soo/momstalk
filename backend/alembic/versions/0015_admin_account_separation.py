"""admin account separation: nullable school fields + admin credentials

Revision ID: 0015
Revises: 0014
Create Date: 2026-06-28
"""
from alembic import op
import sqlalchemy as sa

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN anon_id DROP NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_code DROP NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_name DROP NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN grade DROP NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_type DROP NOT NULL"))

    op.add_column("users", sa.Column("admin_username", sa.String(50), nullable=True))
    op.add_column("users", sa.Column("admin_password_hash", sa.String(128), nullable=True))
    op.create_unique_constraint("uq_users_admin_username", "users", ["admin_username"])


def downgrade():
    op.drop_constraint("uq_users_admin_username", "users", type_="unique")
    op.drop_column("users", "admin_password_hash")
    op.drop_column("users", "admin_username")
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_type SET NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN grade SET NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_name SET NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_code SET NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN anon_id SET NOT NULL"))
