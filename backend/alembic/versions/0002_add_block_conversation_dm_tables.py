"""add block conversation dm tables

Revision ID: 0002
Revises: 0001
Create Date: 2026-06-20
"""
from alembic import op
import sqlalchemy as sa

revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    bind = op.get_bind()
    existing = inspect(bind).get_table_names()
    if 'blocks' in existing:
        return  # create_all이 이미 생성한 경우 건너뜀

    op.create_table(
        'blocks',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('blocked_user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.UniqueConstraint('user_id', 'blocked_user_id', name='uq_block'),
    )

    op.create_table(
        'conversations',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_a_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('user_b_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('last_message_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.UniqueConstraint('user_a_id', 'user_b_id', name='uq_conversation'),
    )

    op.create_table(
        'direct_messages',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('conversation_id', sa.Integer(), sa.ForeignKey('conversations.id'), nullable=False),
        sa.Column('sender_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('is_read', sa.Boolean(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_table('direct_messages')
    op.drop_table('conversations')
    op.drop_table('blocks')
