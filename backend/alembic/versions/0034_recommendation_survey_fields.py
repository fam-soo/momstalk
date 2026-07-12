"""학원 맞춤 추천 Phase 1 확장 — 가입 설문/커리큘럼/후기 세부 필드

기획 문서(맞춤형 학원 큐레이션 v1.0 + 가입 시 추천 설문 표)의 필드를 스키마에
반영한다. 아직 UI는 붙이지 않고 컬럼만 추가한다(Phase 1: 데이터 수집 준비).

- user_children: 가입 시 입력할 learning_goals(학습 목표, 복수), subject_levels
  (과목별 선행 수준/성적) 추가. 숙제 선호/자기주도성/관리형 선호는 새 컬럼을
  만들지 않고 기존 student_traits(행동 키워드 태그) 어휘를 확장해 흡수한다.
- academies: curriculum_focus(커리큘럼 방향), class_style(수업 스타일) 추가.
  강남엄마 홈 탭에 구조화되어 있지 않아 스크래핑 대상은 아니다.
- academy_reviews: feedback_frequency(선생님 피드백 주기), score_change(다니기
  전/후 진도·성적), recommend_to_similar(비슷한 아이에게 추천 여부) 추가.

Revision ID: 0034
Revises: 0033
Create Date: 2026-07-14
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = "0034"
down_revision = "0033"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 자녀 프로필: 가입 시 설문 ────────────────────────────
    op.add_column("user_children", sa.Column("learning_goals", JSONB, nullable=True))
    op.add_column("user_children", sa.Column("subject_levels", JSONB, nullable=True))

    # ── 학원: 커리큘럼/수업 스타일 ──────────────────────────
    op.add_column("academies", sa.Column("curriculum_focus", JSONB, nullable=True))
    op.add_column("academies", sa.Column("class_style", JSONB, nullable=True))

    # ── 후기: 피드백 주기 / 성적 변화 / 추천 여부 ────────────
    op.add_column("academy_reviews", sa.Column("feedback_frequency", sa.String(20), nullable=True))
    op.add_column("academy_reviews", sa.Column("score_change", JSONB, nullable=True))
    op.add_column("academy_reviews", sa.Column("recommend_to_similar", sa.Boolean, nullable=True))


def downgrade() -> None:
    op.drop_column("academy_reviews", "recommend_to_similar")
    op.drop_column("academy_reviews", "score_change")
    op.drop_column("academy_reviews", "feedback_frequency")
    op.drop_column("academies", "class_style")
    op.drop_column("academies", "curriculum_focus")
    op.drop_column("user_children", "subject_levels")
    op.drop_column("user_children", "learning_goals")
