"""미취학 → 초1 전환 유도용 예비 입학연도 컬럼 추가

미취학(school_type=preschool) 자녀가 실제로 초등학교에 입학할 시점을 감지해
"학교 인증 하시겠어요?" 안내를 보여주려면 기준 연도가 필요하다. 생년월일은
과도한 개인정보라 저장하지 않고, 가입 시 학부모가 직접 고른 "초등학교 입학
예정 연도"만 저장한다. 로그인/프로필 조회 시점(_user_profile_with_active_child)에
현재 연도와 비교해 안내 여부를 계산 — 별도 배치/cron 불필요.

Revision ID: 0040
Revises: 0039
Create Date: 2026-07-14
"""
from alembic import op
import sqlalchemy as sa

revision = "0040"
down_revision = "0039"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("user_children", sa.Column("expected_entry_year", sa.Integer(), nullable=True))
    op.add_column("auth_captures", sa.Column("input_expected_entry_year", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("auth_captures", "input_expected_entry_year")
    op.drop_column("user_children", "expected_entry_year")
