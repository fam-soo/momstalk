"""academy_reviews: is_seed 컬럼 추가

Revision ID: 0017
Revises: 0016
Create Date: 2026-06-30
"""
import sqlalchemy as sa
from alembic import op

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "academy_reviews",
        sa.Column("is_seed", sa.Boolean(), nullable=False, server_default="false"),
    )


def downgrade():
    op.drop_column("academy_reviews", "is_seed")
