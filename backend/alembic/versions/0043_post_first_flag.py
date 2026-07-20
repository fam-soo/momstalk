"""작성자의 생애 첫 게시글 여부 — 목록/상세에 "첫 글" 뱃지 표시용

Revision ID: 0043
Revises: 0042
Create Date: 2026-07-15
"""
from alembic import op
import sqlalchemy as sa

revision = "0043"
down_revision = "0042"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("posts", sa.Column("is_first_post", sa.Boolean(), nullable=False, server_default="false"))


def downgrade() -> None:
    op.drop_column("posts", "is_first_post")
