"""선택적 실명제: certified_nickname, school_short_name, nickname_type + profanity_words 테이블

Revision ID: 0007
Revises: 0006
Create Date: 2026-06-27
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.engine.reflection import Inspector

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def _has_column(inspector, table, column):
    return any(c["name"] == column for c in inspector.get_columns(table))


def upgrade() -> None:
    conn = op.get_bind()
    inspector = Inspector.from_engine(conn)
    existing_tables = inspector.get_table_names()

    # users 테이블 — 인증 닉네임 컬럼 추가
    if "users" in existing_tables:
        if not _has_column(inspector, "users", "certified_nickname"):
            op.add_column("users", sa.Column("certified_nickname", sa.String(50), nullable=True))
        if not _has_column(inspector, "users", "school_short_name"):
            op.add_column("users", sa.Column("school_short_name", sa.String(20), nullable=True))

    # posts 테이블 — nickname_type 컬럼 추가 (anon / certified)
    if "posts" in existing_tables:
        if not _has_column(inspector, "posts", "nickname_type"):
            op.add_column("posts", sa.Column(
                "nickname_type", sa.String(10), nullable=False, server_default="anon"
            ))

    # comments 테이블 — nickname_type 컬럼 추가
    if "comments" in existing_tables:
        if not _has_column(inspector, "comments", "nickname_type"):
            op.add_column("comments", sa.Column(
                "nickname_type", sa.String(10), nullable=False, server_default="anon"
            ))

    # profanity_words 테이블 — DB 기반 금칙어 관리
    if "profanity_words" not in existing_tables:
        op.create_table(
            "profanity_words",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("word", sa.String(100), nullable=False, unique=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    op.drop_table("profanity_words")
    op.drop_column("comments", "nickname_type")
    op.drop_column("posts", "nickname_type")
    op.drop_column("users", "school_short_name")
    op.drop_column("users", "certified_nickname")
