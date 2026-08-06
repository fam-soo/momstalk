"""academies.target_school_types — 학원이 실제로 다루는 대상 학교급(복수) 추론값 저장.

school_type 컬럼이 NEIS REALM_SC_NM(학원 계열명)을 저장한 것이라 학교급
필터링에 쓸 수 없던 버그(academy_service.py의 school_type ilike 필터가
항상 0건 반환)를 근본적으로 고치기 위해 별도 컬럼을 둔다.
자세한 배경은 app/models/service_models.py의 Academy.target_school_types 주석 참고.

Revision ID: 0044
Revises: 0043
Create Date: 2026-08-06
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = "0044"
down_revision = "0043"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("academies", sa.Column("target_school_types", JSONB, nullable=True))


def downgrade() -> None:
    op.drop_column("academies", "target_school_types")
