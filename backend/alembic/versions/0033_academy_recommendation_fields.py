"""학원 맞춤 추천 Phase 1 — 성향/성적대 필드 + 강남엄마 스크래핑 연동 컬럼 추가

'맞춤형 학원 큐레이션' 기획(v1.0) Phase 1: 후기·자녀 프로필에 학습 성향/성적대를
수집하기 시작하고, academies 테이블에는 scripts/scrape_gangmom.py(리뷰 제외,
robots.txt 허용 경로만 수집)로 보강한 class_size/founded_year/business_hours를
추가한다. 이 마이그레이션은 컬럼만 추가하며, 추천 UI/알고리즘은 별도로 개발한다.

Revision ID: 0033
Revises: 0032
Create Date: 2026-07-14
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = "0033"
down_revision = "0032"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 자녀 프로필: 학습 성향 태그 + 현재 성적대 ──────────────
    op.add_column("user_children", sa.Column("student_traits", JSONB, nullable=True))
    op.add_column("user_children", sa.Column("score_level", sa.String(20), nullable=True))

    # ── 학원 후기: 작성 시점 기준 수강생 성향 + 성적대 ─────────
    op.add_column("academy_reviews", sa.Column("student_traits", JSONB, nullable=True))
    op.add_column("academy_reviews", sa.Column("score_level", sa.String(20), nullable=True))

    # ── 학원: 강남엄마 스크래핑(리뷰 제외)으로 보강할 컬럼 ─────
    op.add_column("academies", sa.Column("class_size", sa.String(20), nullable=True))
    op.add_column("academies", sa.Column("founded_year", sa.Integer, nullable=True))
    op.add_column("academies", sa.Column("business_hours", sa.String(100), nullable=True))


def downgrade() -> None:
    op.drop_column("academies", "business_hours")
    op.drop_column("academies", "founded_year")
    op.drop_column("academies", "class_size")
    op.drop_column("academy_reviews", "score_level")
    op.drop_column("academy_reviews", "student_traits")
    op.drop_column("user_children", "score_level")
    op.drop_column("user_children", "student_traits")
