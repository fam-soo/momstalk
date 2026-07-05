"""auth_captures: 이미지를 Supabase Storage 대신 DB에 직접 저장

배경: Supabase Storage 왕복(백엔드→Supabase 업로드, 관리자 조회 시 Supabase→
백엔드 재다운로드)이 캡처 업로드 오류의 반복 원인 중 하나였음. 이미지가
작고(리사이즈된 알림장 사진) 승인/반려 즉시 삭제되는 단명 데이터라는 점에서
별도 오브젝트 스토리지 없이 Postgres BYTEA로 직접 저장해 흐름을 단순화.

Revision ID: 0022
Revises: 0021
Create Date: 2026-07-05
"""
from alembic import op
import sqlalchemy as sa

revision = "0022"
down_revision = "0021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("auth_captures", sa.Column("image_data", sa.LargeBinary, nullable=True))
    op.add_column("auth_captures", sa.Column("image_content_type", sa.String(30), nullable=True))
    op.alter_column("auth_captures", "s3_key", nullable=True)


def downgrade() -> None:
    op.alter_column("auth_captures", "s3_key", nullable=False)
    op.drop_column("auth_captures", "image_content_type")
    op.drop_column("auth_captures", "image_data")
