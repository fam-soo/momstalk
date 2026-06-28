"""review: subjects/teacher_styles JSONB (multi-select)

Revision ID: 0013
Revises: 0012
Create Date: 2026-06-28
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 기존 단일 문자열 컬럼 → JSONB 배열 컬럼으로 교체
    op.add_column(
        "academy_reviews",
        sa.Column("subjects", postgresql.JSONB(), nullable=True),
    )
    op.add_column(
        "academy_reviews",
        sa.Column("teacher_styles", postgresql.JSONB(), nullable=True),
    )
    # 기존 데이터 마이그레이션: 값이 있으면 배열로 변환
    op.execute(
        "UPDATE academy_reviews SET subjects = to_jsonb(ARRAY[subject]) WHERE subject IS NOT NULL AND subject <> ''"
    )
    op.execute(
        "UPDATE academy_reviews SET teacher_styles = to_jsonb(ARRAY[teacher_style]) WHERE teacher_style IS NOT NULL AND teacher_style <> ''"
    )
    op.drop_column("academy_reviews", "subject")
    op.drop_column("academy_reviews", "teacher_style")


def downgrade() -> None:
    op.add_column(
        "academy_reviews",
        sa.Column("subject", sa.String(30), nullable=True),
    )
    op.add_column(
        "academy_reviews",
        sa.Column("teacher_style", sa.String(30), nullable=True),
    )
    op.execute(
        "UPDATE academy_reviews SET subject = subjects->>0 WHERE subjects IS NOT NULL"
    )
    op.execute(
        "UPDATE academy_reviews SET teacher_style = teacher_styles->>0 WHERE teacher_styles IS NOT NULL"
    )
    op.drop_column("academy_reviews", "subjects")
    op.drop_column("academy_reviews", "teacher_styles")
