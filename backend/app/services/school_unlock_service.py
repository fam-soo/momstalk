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

from app.models.service_models import User, UserChild

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
