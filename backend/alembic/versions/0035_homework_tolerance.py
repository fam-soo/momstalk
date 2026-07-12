"""학원 추천받기 설문 — user_children.homework_tolerance 추가

Revision ID: 0035
Revises: 0034
Create Date: 2026-07-14
"""
from alembic import op
import sqlalchemy as sa

revision = "0035"
down_revision = "0034"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("user_children", sa.Column("homework_tolerance", sa.String(20), nullable=True))


def downgrade() -> None:
    op.drop_column("user_children", "homework_tolerance")
