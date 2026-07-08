"""기존 정회원 중 UserChild가 없는 계정을 users.school_code 기준으로 백필

capture_service.approve_capture / _auto_approve_trusted가 최초 가입
승인(capture_type='initial') 시 user_children 행을 만들지 않고 legacy
users.school_code/school_name/grade만 채우던 버그가 있었다(이번 세션에서
코드는 고쳤음). 그 결과 두 번째 자녀를 추가한 적 없는 정회원은
UserChild가 아예 없어, 학교 게시판 언락/관리자 대시보드/학교별 인원
조회처럼 UserChild.school_code 기준으로 집계하는 모든 화면에서 누락되어
보였다. 코드 수정은 이후 가입자에게만 적용되므로, 이미 가입된 기존
정회원은 이 마이그레이션으로 한 번 백필한다.

Revision ID: 0028
Revises: 0027
Create Date: 2026-07-09
"""
from alembic import op
import sqlalchemy as sa

revision = "0028"
down_revision = "0027"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(sa.text("""
        INSERT INTO user_children (user_id, school_code, school_name, grade, class_num, school_type, region, created_at)
        SELECT u.id, u.school_code, u.school_name, u.grade, u.class_num, u.school_type, u.region, NOW()
        FROM users u
        WHERE u.member_grade = 'member'
          AND u.is_admin = false
          AND u.school_code IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM user_children uc
              WHERE uc.user_id = u.id AND uc.school_code = u.school_code
          )
    """))
    # 방금 백필한 행을 active_child가 없는 유저의 active_child로 연결
    op.execute(sa.text("""
        UPDATE users u
        SET active_child_id = uc.id
        FROM user_children uc
        WHERE u.active_child_id IS NULL
          AND uc.user_id = u.id
          AND uc.school_code = u.school_code
    """))


def downgrade() -> None:
    # 백필 데이터를 안전하게 되돌릴 방법이 없다 (원래 없던 행이라는 표식이 없음) — no-op
    pass
