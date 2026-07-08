"""posts: target_region 컬럼 추가 + school_code nullable 전환 (공지사항 지역/전체 타겟팅)

공지사항(board_type='notice')을 지역 게시판/학교 게시판/전체 게시판
상단에 고정 노출하기 위해 타겟 범위를 명확히 구분해야 한다.
- target_school_code 지정 → school_code에 저장 (학교 단위 공지)
- target_region 지정(학교 미지정) → target_region에 저장, school_code는 NULL (지역 단위 공지)
- 둘 다 미지정 → school_code, target_region 모두 NULL (전체 공지)

일반 게시글은 항상 실제 school_code를 가지므로 영향 없음.

Revision ID: 0026
Revises: 0025
Create Date: 2026-07-08
"""
from alembic import op
import sqlalchemy as sa

revision = "0026"
down_revision = "0025"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("posts", sa.Column("target_region", sa.String(50), nullable=True))
    op.alter_column("posts", "school_code", existing_type=sa.String(20), nullable=True)


def downgrade() -> None:
    op.alter_column("posts", "school_code", existing_type=sa.String(20), nullable=False)
    op.drop_column("posts", "target_region")
