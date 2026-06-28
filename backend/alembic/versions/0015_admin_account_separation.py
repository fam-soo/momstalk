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
    # school_code, school_name, grade, school_type, anon_id -> nullable
    # raw SQL이 가장 안전 (existing_type 추론 불필요)
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN anon_id DROP NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_code DROP NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_name DROP NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN grade DROP NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_type DROP NOT NULL"))

    # 관리자 전용 자격증명 컬럼 추가
    op.add_column("users", sa.Column("admin_username", sa.String(50), nullable=True))
    op.add_column("users", sa.Column("admin_password_hash", sa.String(128), nullable=True))
    op.create_unique_constraint("uq_users_admin_username", "users", ["admin_username"])

    # 기본 관리자 계정 생성 (초기 PW: Momstalk@2025!)
    import os
    admin_pw = os.environ.get("ADMIN_INIT_PASSWORD", "Momstalk@2025!")
    hashed = _pwd.hash(admin_pw)
    op.execute(
        sa.text(
            "INSERT INTO users "
            "(anon_id, nickname, school_code, school_name, grade, school_type, "
            " is_admin, member_grade, admin_username, admin_password_hash, "
            " manner_score, created_at) "
            "VALUES "
            "(NULL, :nickname, NULL, NULL, NULL, NULL, "
            " TRUE, 'admin', 'admin', :pw_hash, 365, NOW()) "
            "ON CONFLICT DO NOTHING"
        ).bindparams(pw_hash=hashed, nickname="운영자")
    )


def downgrade():
    op.drop_constraint("uq_users_admin_username", "users", type_="unique")
    op.drop_column("users", "admin_password_hash")
    op.drop_column("users", "admin_username")
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_type SET NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN grade SET NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_name SET NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN school_code SET NOT NULL"))
    op.execute(sa.text("ALTER TABLE users ALTER COLUMN anon_id SET NOT NULL"))
