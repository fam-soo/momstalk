"""user_children 테이블 추가, active_child_id, academy_review_count 컬럼 추가

Revision ID: 0019
Revises: 0018
Create Date: 2026-07-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0019"
down_revision = "0018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. user_children 테이블 생성
    op.create_table(
        "user_children",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("school_code", sa.String(20), nullable=True),
        sa.Column("school_name", sa.String(100), nullable=True),
        sa.Column("grade", sa.Integer, nullable=True),
        sa.Column("class_num", sa.Integer, nullable=True),
        sa.Column("school_type", sa.String(10), nullable=True),
        sa.Column("region", sa.String(50), nullable=True),
        sa.Column("created_at", sa.DateTime, server_default=sa.text("NOW()")),
    )
    op.create_index("ix_user_children_user_id", "user_children", ["user_id"])

    # 2. users 테이블에 active_child_id 추가
    op.add_column(
        "users",
        sa.Column("active_child_id", sa.Integer, sa.ForeignKey("user_children.id", ondelete="SET NULL"), nullable=True),
    )

    # 3. users 테이블에 academy_review_count 추가
    op.add_column(
        "users",
        sa.Column("academy_review_count", sa.Integer, nullable=False, server_default="0"),
    )

    # 4. 기존 유저(school_code 있는 유저)를 user_children으로 마이그레이션
    op.execute("""
        INSERT INTO user_children (user_id, school_code, school_name, grade, class_num, school_type, region)
        SELECT id, school_code, school_name, grade, class_num, school_type, region
        FROM users
        WHERE school_code IS NOT NULL
    """)

    op.execute("""
        UPDATE users u
        SET active_child_id = (
            SELECT id FROM user_children uc WHERE uc.user_id = u.id ORDER BY uc.id LIMIT 1
        )
        WHERE u.school_code IS NOT NULL
    """)

    # 5. 기존 후기 작성자의 academy_review_count 업데이트
    op.execute("""
        UPDATE users u
        SET academy_review_count = (
            SELECT COUNT(*)
            FROM academy_reviews ar
            WHERE ar.author_id = u.id AND ar.is_seed = false
        )
    """)


def downgrade() -> None:
    op.drop_column("users", "academy_review_count")
    op.drop_column("users", "active_child_id")
    op.drop_index("ix_user_children_user_id", table_name="user_children")
    op.drop_table("user_children")
