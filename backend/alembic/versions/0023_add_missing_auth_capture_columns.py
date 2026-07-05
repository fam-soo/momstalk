"""auth_captures: 누락된 input_school_type, input_region 컬럼 추가

배경: 두 컬럼 모두 SQLAlchemy 모델(app/models/service_models.py)에는
오래전부터 정의되어 있었지만 이를 실제로 추가하는 Alembic 마이그레이션이
한 번도 작성되지 않아 프로덕션 DB에는 컬럼 자체가 존재하지 않았다.
submit_capture()가 AuthCapture 전체 컬럼을 SELECT하는 모든 경로(최초 가입
인증, 자녀 추가 인증)에서 매번
"column auth_captures.input_school_type does not exist" 로 500이 발생해
캡처 업로드가 항상 실패하고 있었다 — 최근 며칠간 조사했던 "네트워크 오류"의
실제 원인이 CORS나 콜드 스타트가 아니라 이 스키마 드리프트였음.

Revision ID: 0023
Revises: 0022
Create Date: 2026-07-05
"""
from alembic import op
import sqlalchemy as sa

revision = "0023"
down_revision = "0022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    existing_cols = {c["name"] for c in inspector.get_columns("auth_captures")}

    if "input_school_type" not in existing_cols:
        op.add_column("auth_captures", sa.Column("input_school_type", sa.String(20), nullable=True))
    if "input_region" not in existing_cols:
        op.add_column("auth_captures", sa.Column("input_region", sa.String(50), nullable=True))


def downgrade() -> None:
    op.drop_column("auth_captures", "input_region")
    op.drop_column("auth_captures", "input_school_type")
