"""매년 3월 1일 학년 자동 승급.

별도 cron 인프라 없이, get_current_user 의존성(모든 인증 API 공통 경로)에서
매 요청마다 아주 가벼운 조건만 확인하고 — 아직 3/1이 안 지났거나 이미 올해
승급을 마쳤으면 그냥 리턴 — 승급 대상일 때만 자녀 목록을 조회해 실제로
갱신한다. 정확히 3/1 0시가 아니라 "3/1 이후 첫 요청 시점"에 적용되지만
실사용에는 차이가 없다.

학년급별 최대 학년(초6/중3/고3)을 넘기면 졸업으로 보고 학교 정보를
삭제한다 — 다음 단계 학교는 자동으로 알 수 없어(초→중, 중→고 진학) 새로
학교 인증을 받아야 하기 때문. 미취학은 대상이 아니다(expected_entry_year로
별도 안내).
"""
from datetime import date

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.service_models import User, UserChild

_MAX_GRADE = {"elementary": 6, "middle": 3, "high": 3}


async def maybe_promote_grade(user: User, db: AsyncSession) -> None:
    today = date.today()
    if (today.month, today.day) < (3, 1):
        return
    current_year = today.year
    if user.grade_promoted_year and user.grade_promoted_year >= current_year:
        return

    try:
        children = (await db.execute(
            select(UserChild).where(UserChild.user_id == user.id)
        )).scalars().all()

        for child in children:
            if child.school_type == "preschool" or child.grade is None:
                continue
            cap = _MAX_GRADE.get(child.school_type)
            new_grade = child.grade + 1
            if cap and new_grade > cap:
                # 졸업 — 다음 학교를 자동으로 알 수 없으니 학교 정보를 비우고
                # 새로 인증받도록 한다.
                child.school_code = None
                child.school_name = None
                child.grade = None
                child.class_num = None
                child.school_type = None
            else:
                child.grade = new_grade

        if children:
            active = next((c for c in children if c.id == user.active_child_id), None)
            if active:
                # deprecated 레거시 필드도 동기화 — _user_profile_with_active_child()가
                # 우선 덮어쓰긴 하지만, 그 전까지 다른 코드가 이 필드를 직접 읽는 경우 대비.
                user.grade = active.grade
                user.school_code = active.school_code
                user.school_name = active.school_name
                user.school_type = active.school_type

        user.grade_promoted_year = current_year
        await db.commit()
    except Exception:
        # 이 부가 기능이 실패해도 인증 자체는 절대 깨지면 안 된다. rollback은
        # 세션의 모든 객체 속성을 expired 상태로 만드는데, 그 상태로 두면 이후
        # 코드가 user.xxx를 동기적으로 읽을 때 SQLAlchemy가 자동으로 재조회를
        # 시도하다가 (await 없이 실행되는 지점이라) 비동기 드라이버의 greenlet
        # 컨텍스트가 없어 MissingGreenlet으로 죽는다 — 그래서 반드시 명시적으로
        # await refresh까지 마쳐서 인증 흐름에 안전하게 되돌려준다.
        await db.rollback()
        await db.refresh(user)
