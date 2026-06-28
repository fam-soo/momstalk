"""admin account separation: nullable school fields + admin credentials

Revision ID: 0015
Revises: 0014
Create Date: 2026-06-28
"""
from alembic import op
import sqlalchemy as sa
from passlib.context import CryptContext

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None

_pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")


def upgrade():
    # school_code, school_name, grade, school_type, anon_id → nullable (관리자 계정 수용)
    op.alter_column("users", "anon_id", nullable=True)
    op.alter_column("users", "school_code", nullable=True)
    op.alter_column("users", "school_name", nullable=True)
    op.alter_column("users", "grade", nullable=True)
    op.alter_column("users", "school_type", nullable=True)

    # 관리자 전용 자격증명 컬럼 추가
    op.add_column("users", sa.Column("admin_username", sa.String(50), nullable=True, unique=True))
    op.add_column("users", sa.Column("admin_password_hash", sa.String(128), nullable=True))

    # member_grade 'admin' 허용 (check constraint 없으므로 별도 작업 불필요)

    # 기본 관리자 계정 생성
    # 초기 비밀번호: Momstalk@2025! — 첫 로그인 후 변경 필요
    import os
    admin_pw = os.environ.get("ADMIN_INIT_PASSWORD", "Momstalk@2025!")
    hashed = _pwd.hash(admin_pw)
    op.execute(
        sa.text("""
            INSERT INTO users (
                anon_id, nickname, school_code, school_name, grade, school_type,
                is_admin, member_grade, admin_username, admin_password_hash,
                manner_score, created_at
            ) VALUES (
                NULL, '운영자', NULL, NULL, NULL, NULL,
                TRUE, 'admin', 'admin', :pw_hash,
                365, NOW()
            )
            ON CONFLICT DO NOTHING
        """).bindparams(pw_hash=hashed)
    )


def downgrade():
    op.drop_column("users", "admin_password_hash")
    op.drop_column("users", "admin_username")
    op.alter_column("users", "school_type", nullable=False)
    op.alter_column("users", "grade", nullable=False)
    op.alter_column("users", "school_name", nullable=False)
    op.alter_column("users", "school_code", nullable=False)
    op.alter_column("users", "anon_id", nullable=False)
