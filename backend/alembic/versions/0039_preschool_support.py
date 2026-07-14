"""미취학 학부모 지원 — auth_captures 학교 필수 컬럼 nullable화

미취학 아동은 학교 자체가 없어 학교 검색/인증 단계를 생략한다. 지금까지
auth_captures.input_school_code/input_school_name/input_grade가 NOT NULL이라
캡처 업로드 자체가 학교 정보 없이는 불가능했다 — 이 세 컬럼을 nullable로
바꿔 미취학 가입(capture_type=initial/child_add, school_type=preschool)이
학교 정보 없이도 제출될 수 있게 한다.

UserChild/User 쪽은 이미 전부 nullable이라 별도 변경이 필요 없다.

Revision ID: 0039
Revises: 0038
Create Date: 2026-07-14
"""
from alembic import op
import sqlalchemy as sa

revision = "0039"
down_revision = "0038"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column("auth_captures", "input_school_code", existing_type=sa.String(20), nullable=True)
    op.alter_column("auth_captures", "input_school_name", existing_type=sa.String(100), nullable=True)
    op.alter_column("auth_captures", "input_grade", existing_type=sa.Integer(), nullable=True)


def downgrade() -> None:
    op.alter_column("auth_captures", "input_grade", existing_type=sa.Integer(), nullable=False)
    op.alter_column("auth_captures", "input_school_name", existing_type=sa.String(100), nullable=False)
    op.alter_column("auth_captures", "input_school_code", existing_type=sa.String(20), nullable=False)
