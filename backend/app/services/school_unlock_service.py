"""학교 게시판 언락 — 학원 후기 언락과 같은 "기여 기반" 잠금 메커니즘.

지역/학원 게시판은 자유롭게 열어두되, 학교 게시판(school/grade)은 같은
학교 소속 정회원이 일정 인원(SCHOOL_UNLOCK_THRESHOLD) 이상 모여야 잠금
해제된다. 초대 링크로 가입한 유저는 즉시 member_grade='member'로
승급되므로(app/services/invite_service.py), 이 카운트에는 "직접 사진
인증을 마친 사람"과 "인증회원이 초대해서 즉시 정회원이 된 사람"이
자연스럽게 함께 포함된다 — 초대 체인 자체가 신뢰 전파이기 때문에 별도
분기 없이 member_grade == 'member' 카운트만으로 충분하다.
"""
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.service_models import School, User, UserChild

# 학교당 언락 기준 인원 — 우선 고정값으로 시작, 추후 학교 규모 비례 등으로 조정 가능.
SCHOOL_UNLOCK_THRESHOLD = 10


async def count_school_members(school_code: str, db: AsyncSession) -> int:
    """해당 학교 소속(자녀 등록 기준) 정회원 수. 다자녀인 경우 그 학교에 자녀를 등록한
    것만으로 카운트되며(활성 자녀 여부와 무관), 관리자는 제외한다."""
    if not school_code:
        return 0
    result = await db.execute(
        select(func.count(func.distinct(UserChild.user_id)))
        .join(User, User.id == UserChild.user_id)
        .where(
            UserChild.school_code == school_code,
            User.member_grade == "member",
            User.is_admin.is_(False),
        )
    )
    return result.scalar() or 0


async def get_unlock_status(school_code: str, db: AsyncSession) -> dict:
    count = await count_school_members(school_code, db)
    unlocked = count >= SCHOOL_UNLOCK_THRESHOLD
    return {
        "school_code": school_code,
        "member_count": count,
        "threshold": SCHOOL_UNLOCK_THRESHOLD,
        "unlocked": unlocked,
        "remaining": max(0, SCHOOL_UNLOCK_THRESHOLD - count),
    }


async def get_unlock_leaderboard(db: AsyncSession, limit: int = 5) -> dict:
    """아직 학교 게시판이 잠긴 유저에게 "우리 학교도 빨리 모으자"는 경쟁심을
    자극하기 위해, 이미 열린 학교 수와 인원 상위 학교 목록을 보여준다.
    개인정보 없이 학교명·지역·인원수만 노출 — count_school_members와
    동일한 기준(UserChild.school_code + member_grade='member', 관리자 제외)."""
    rows = (await db.execute(
        select(UserChild.school_code, func.count(func.distinct(UserChild.user_id)).label("cnt"))
        .join(User, User.id == UserChild.user_id)
        .where(User.member_grade == "member", User.is_admin.is_(False), UserChild.school_code.isnot(None))
        .group_by(UserChild.school_code)
        .having(func.count(func.distinct(UserChild.user_id)) >= SCHOOL_UNLOCK_THRESHOLD)
        .order_by(func.count(func.distinct(UserChild.user_id)).desc())
    )).all()

    unlocked_codes = [r.school_code for r in rows]
    top_rows = rows[:limit]
    names: dict[str, tuple[str, str | None]] = {}
    if top_rows:
        school_infos = (await db.execute(
            select(School.school_code, School.school_name, School.region)
            .where(School.school_code.in_([r.school_code for r in top_rows]))
        )).all()
        names = {s.school_code: (s.school_name, s.region) for s in school_infos}

    return {
        "unlocked_school_count": len(unlocked_codes),
        "top_schools": [
            {
                "school_code": r.school_code,
                "school_name": names.get(r.school_code, (r.school_code, None))[0],
                "region": names.get(r.school_code, (r.school_code, None))[1],
                "member_count": r.cnt,
            }
            for r in top_rows
        ],
    }
