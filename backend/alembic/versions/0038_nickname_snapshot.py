"""posts/comments/academy_reviews에 nickname_snapshot 추가 (작성 시점 닉네임 고정)

지금까지는 게시글/댓글/후기의 작성자 표시명을 매번 users.nickname(또는
certified_nickname)에서 실시간으로 조회했다. 그래서 유저가 닉네임을 바꾸면
과거에 쓴 글까지 전부 새 닉네임으로 바뀌어 보이는 문제가 있었다 — 게시글
작성 당시 닉네임으로 고정되어야 하는데 그렇지 않았음.

이 마이그레이션은 세 테이블에 nickname_snapshot 컬럼을 추가하고, 기존
행에 대해 "현재 시점 기준" 닉네임으로 최대한 채워둔다(과거 실제 닉네임은
기록이 없어 알 수 없으므로, 지금부터라도 고정되도록 하는 백필). 이후
생성되는 글은 서비스 코드에서 작성 시점 닉네임을 그대로 저장한다.

Revision ID: 0038
Revises: 0037
Create Date: 2026-07-13
"""
from alembic import op
import sqlalchemy as sa

revision = "0038"
down_revision = "0037"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("posts", sa.Column("nickname_snapshot", sa.String(50), nullable=True))
    op.add_column("comments", sa.Column("nickname_snapshot", sa.String(50), nullable=True))
    op.add_column("academy_reviews", sa.Column("nickname_snapshot", sa.String(50), nullable=True))

    # posts: nickname_type='certified' → certified_nickname 우선, 아니면 nickname.
    # 그 외 익명이 아닌 글(grade/notice처럼 항상 실명 고정인 게시판)은 nickname.
    op.execute(sa.text("""
        UPDATE posts p SET nickname_snapshot = COALESCE(u.certified_nickname, u.nickname)
        FROM users u WHERE u.id = p.author_id AND p.nickname_type = 'certified'
    """))
    op.execute(sa.text("""
        UPDATE posts p SET nickname_snapshot = u.nickname
        FROM users u WHERE u.id = p.author_id AND p.nickname_type <> 'certified' AND p.is_anonymous = false
    """))

    op.execute(sa.text("""
        UPDATE comments c SET nickname_snapshot = COALESCE(u.certified_nickname, u.nickname)
        FROM users u WHERE u.id = c.author_id AND c.nickname_type = 'certified'
    """))
    op.execute(sa.text("""
        UPDATE comments c SET nickname_snapshot = u.nickname
        FROM users u WHERE u.id = c.author_id AND c.nickname_type <> 'certified' AND c.is_anonymous = false
    """))

    # academy_reviews: 기존 로직은 nickname_type과 무관하게 익명이 아니면 nickname만 사용
    op.execute(sa.text("""
        UPDATE academy_reviews r SET nickname_snapshot = u.nickname
        FROM users u WHERE u.id = r.author_id AND r.is_anonymous = false
    """))


def downgrade() -> None:
    op.drop_column("academy_reviews", "nickname_snapshot")
    op.drop_column("comments", "nickname_snapshot")
    op.drop_column("posts", "nickname_snapshot")
