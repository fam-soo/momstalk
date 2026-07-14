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

from app.models.service_models import AcademyReview, School, User, UserChild

# 학교당 언락 기준 인원 — 우선 고정값으로 시작, 추후 학교 규모 비례 등으로 조정 가능.
SCHOOL_UNLOCK_THRESHOLD = 10
# 학원 후기를 1개 이상 남긴 정회원 기준 인원 — 조건 강화판. 단순히 학교
# 인증만 받으면 되던 기존 기준(SCHOOL_UNLOCK_THRESHOLD)은 남겨두고 OR로
# 묶어서, 이미 예전 기준으로 열려 있던 학교는 계속 열린 채로 유지된다
# (raw member_count는 한 번 넘으면 사실상 줄어들 일이 없어 자연스럽게
# grandfathering된다). 새로 채워지는 학교부터는 후기 작성 인원 기준을
# 만족해야 열린다.
SCHOOL_UNLOCK_REVIEW_THRESHOLD = 10


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


async def count_school_members_with_review(school_code: str, db: AsyncSession) -> int:
    """해당 학교 소속 정회원 중 학원 후기(seed 제외)를 1개 이상 작성한 인원 수."""
    if not school_code:
        return 0
    result = await db.execute(
        select(func.count(func.distinct(UserChild.user_id)))
        .join(User, User.id == UserChild.user_id)
        .join(AcademyReview, AcademyReview.author_id == User.id)
        .where(
            UserChild.school_code == school_code,
            User.member_grade == "member",
            User.is_admin.is_(False),
            AcademyReview.is_seed.isnot(True),
        )
    )
    return result.scalar() or 0


async def get_unlock_status(school_code: str, db: AsyncSession) -> dict:
    legacy_count = await count_school_members(school_code, db)
    review_count = await count_school_members_with_review(school_code, db)
    unlocked = legacy_count >= SCHOOL_UNLOCK_THRESHOLD or review_count >= SCHOOL_UNLOCK_REVIEW_THRESHOLD
    return {
        "school_code": school_code,
        "member_count": review_count,
        "threshold": SCHOOL_UNLOCK_REVIEW_THRESHOLD,
        "unlocked": unlocked,
        "remaining": max(0, SCHOOL_UNLOCK_REVIEW_THRESHOLD - review_count),
    }


async def get_unlock_leaderboard(db: AsyncSession, limit: int = 5) -> dict:
    """아직 학교 게시판이 잠긴 유저에게 "우리 학교도 빨리 모으자"는 경쟁심을
    자극하기 위해, 이미 열린 학교 수와 인원 상위 학교 목록을 보여준다.
    개인정보 없이 학교명·지역·인원수만 노출 — count_school_members와
    동일한 기준(UserChild.school_code + member_grade='member', 관리자 제외)."""
    legacy_rows = (await db.execute(
        select(UserChild.school_code, func.count(func.distinct(UserChild.user_id)).label("cnt"))
        .join(User, User.id == UserChild.user_id)
        .where(User.member_grade == "member", User.is_admin.is_(False), UserChild.school_code.isnot(None))
        .group_by(UserChild.school_code)
        .having(func.count(func.distinct(UserChild.user_id)) >= SCHOOL_UNLOCK_THRESHOLD)
    )).all()
    review_rows = (await db.execute(
        select(UserChild.school_code, func.count(func.distinct(UserChild.user_id)).label("cnt"))
        .join(User, User.id == UserChild.user_id)
        .join(AcademyReview, AcademyReview.author_id == User.id)
        .where(
            User.member_grade == "member", User.is_admin.is_(False),
            UserChild.school_code.isnot(None), AcademyReview.is_seed.isnot(True),
        )
        .group_by(UserChild.school_code)
        .having(func.count(func.distinct(UserChild.user_id)) >= SCHOOL_UNLOCK_REVIEW_THRESHOLD)
    )).all()

    # 두 기준(레거시 인증 인원 / 후기 작성 인원) 중 하나라도 만족하면 열린 것 —
    # 표시 인원수는 둘 중 더 큰 값을 사용.
    counts: dict[str, int] = {}
    for r in legacy_rows:
        counts[r.school_code] = max(counts.get(r.school_code, 0), r.cnt)
    for r in review_rows:
        counts[r.school_code] = max(counts.get(r.school_code, 0), r.cnt)

    unlocked_codes = list(counts.keys())
    top_rows = sorted(
        (type("Row", (), {"school_code": k, "cnt": v}) for k, v in counts.items()),
        key=lambda r: -r.cnt,
    )[:limit]
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
