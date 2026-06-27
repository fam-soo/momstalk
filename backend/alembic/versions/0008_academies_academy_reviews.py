"""academies and academy_reviews tables

Revision ID: 0008
Revises: 0007
Create Date: 2026-06-27
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "academies",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("neis_academy_code", sa.String(30), nullable=True, unique=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("region", sa.String(50), nullable=True),
        sa.Column("address", sa.String(200), nullable=True),
        sa.Column("phone", sa.String(20), nullable=True),
        sa.Column("subjects", postgresql.JSONB(), nullable=True),
        sa.Column("school_type", sa.String(20), nullable=True),
        sa.Column("is_b2b", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("b2b_expires_at", sa.DateTime(), nullable=True),
        sa.Column("review_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("avg_rating", sa.Numeric(3, 2), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("now()")),
    )
    op.create_index("ix_academies_region", "academies", ["region"])
    op.create_index("ix_academies_name", "academies", ["name"])

    op.create_table(
        "academy_reviews",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("academy_id", sa.Integer(), sa.ForeignKey("academies.id", ondelete="CASCADE"), nullable=False),
        sa.Column("author_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("subject", sa.String(30), nullable=True),
        sa.Column("teacher_style", sa.String(30), nullable=True),
        sa.Column("homework_level", sa.String(20), nullable=True),
        sa.Column("score_improvement", sa.String(30), nullable=True),
        sa.Column("review_text", sa.Text(), nullable=False),
        sa.Column("rating", sa.SmallInteger(), nullable=False),
        sa.Column("nickname_type", sa.String(10), nullable=False, server_default="anon"),
        sa.Column("is_anonymous", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("report_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_hidden", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("now()")),
    )
    op.create_index("ix_academy_reviews_academy_id", "academy_reviews", ["academy_id"])
    op.create_index("ix_academy_reviews_author_id", "academy_reviews", ["author_id"])


def downgrade() -> None:
    op.drop_table("academy_reviews")
    op.drop_table("academies")
