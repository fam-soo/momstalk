"""fix manner_score default to 365

Revision ID: 0014
Revises: 0013
Create Date: 2026-06-28
"""
from alembic import op
import sqlalchemy as sa

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None


def upgrade():
    # Change column default to 365 (= 36.5°C in ×10 scale)
    op.alter_column("users", "manner_score", server_default="365")
    # Reset any users still on old-scale values (0–99) to the new default
    op.execute("UPDATE users SET manner_score = 365 WHERE manner_score < 100")


def downgrade():
    op.alter_column("users", "manner_score", server_default="36")
    op.execute("UPDATE users SET manner_score = 36 WHERE manner_score = 365")
