"""add mention_tags to posts

Revision ID: 0001
Revises:
Create Date: 2026-06-20
"""
from alembic import op
import sqlalchemy as sa

revision = '0001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('posts', sa.Column('mention_tags', sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column('posts', 'mention_tags')
