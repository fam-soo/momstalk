"""users.academy_review_count 재동기화 (실제 후기 수와 어긋난 계정 복구)

일부 기존 사용자가 학원 후기를 작성해뒀는데도 users.academy_review_count가
0으로 표시되어, 후기 열람 쿼터(_academy_unlock_quota)가 "0건"으로 계산되고
결과적으로 해금 가능한 학원 수가 실제보다 적게 잡히는 문제가 보고됐다.

이 카운터는 create_review()가 성공할 때만 +1 되는 비정규화 값이라, 아래
경우 실제 academy_reviews 행 수와 어긋날 수 있다:
  - Supabase SQL Editor로 후기를 직접 INSERT한 경우(시드 후기 작성 워크플로에서
    이렇게 안내됨) — ORM을 거치지 않아 카운터가 전혀 증가하지 않음
  - 0019에서 최초 백필했지만 그 이후 어떤 이유로든 카운터 증가가 누락된 경우

0019가 처음 이 컬럼을 채울 때 썼던 것과 동일한 방식으로, 전체 유저를 대상으로
실제 academy_reviews(is_seed=false) 개수 기준으로 다시 맞춘다. 멱등 연산이라
여러 번 실행해도 안전하다.

Revision ID: 0032
Revises: 0031
Create Date: 2026-07-13
"""
from alembic import op
import sqlalchemy as sa

revision = "0032"
down_revision = "0031"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(sa.text("""
        UPDATE users u
        SET academy_review_count = (
            SELECT COUNT(*)
            FROM academy_reviews ar
            WHERE ar.author_id = u.id AND ar.is_seed = false
        )
        WHERE u.academy_review_count <> (
            SELECT COUNT(*)
            FROM academy_reviews ar
            WHERE ar.author_id = u.id AND ar.is_seed = false
        )
    """))


def downgrade() -> None:
    # 원래 값을 보존하는 표식이 없어 되돌릴 방법이 없다 — no-op
    pass
