import json
from decimal import Decimal
from typing import Optional

import sqlalchemy as sa
from sqlalchemy import select, func
from sqlalchemy.dialects.postgresql import JSONB as PGJSONB
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.profanity import check_profanity
from app.models.service_models import Academy, AcademyReview, User
from app.schemas.academy import AcademyReviewCreate, AcademyReviewResponse, AcademyResponse
from app.services import neis_service


_SUBJECT_KEYWORDS: dict[str, list[str]] = {
    "수학": ["수학"],
    "영어": ["영어", "영어회화", "영어전문"],
    "국어": ["국어", "논술", "독서논술"],
    "과학": ["과학", "물리", "화학", "생물"],
    "음악": ["음악", "피아노", "바이올린", "플루트", "첼로", "드럼", "성악", "기타레슨"],
    "미술": ["미술", "드로잉", "조형", "입시미술"],
    "체육": ["체육", "태권도", "수영", "발레", "무용", "유도", "검도", "축구", "농구", "야구"],
    "코딩": ["코딩", "프로그래밍", "로봇", "SW", "소프트웨어", "컴퓨터"],
}


def _detect_subjects_from_name(name: str) -> list[str]:
    """학원 이름에서 과목 키워드를 감지해 subject 목록 반환."""
    detected = []
    name_lower = name.lower()
    for subject, keywords in _SUBJECT_KEYWORDS.items():
        if any(kw in name for kw in keywords) or any(kw.lower() in name_lower for kw in keywords):
            detected.append(subject)
    return detected


async def search_academies(
    db: AsyncSession,
    name: Optional[str] = None,
    region: Optional[str] = None,
    subjects: Optional[list[str]] = None,   # 복수 과목 필터
    school_level: Optional[str] = None,      # 초등|중등|고등
    reviewer_school: Optional[str] = None,   # 후기 작성자 아이의 학교명
    reviewer_grades: Optional[list[int]] = None,  # 후기 작성자 아이의 학년(들)
) -> list[AcademyResponse]:
    """DB 우선 검색 → 결과 없으면 NEIS API 조회 후 DB 캐싱.

    이름 검색 시 region 필터 미적용 (전국 검색) — region은 지역 목록 조회에만 사용.
    """
    filters = []
    if name:
        filters.append(Academy.name.ilike(f"%{name}%"))
    if region:
        filters.append(Academy.region.ilike(f"%{region}%"))
    if subjects:
        # 선택한 과목 중 하나라도 포함하면 표시 (OR 조건)
        # JSONB @> 체크 + 학원명 키워드 fallback (subjects 미입력 학원 대응)
        subject_filters = []
        for s in subjects:
            kws = _SUBJECT_KEYWORDS.get(s, [s])
            name_kw_filters = [Academy.name.ilike(f"%{kw}%") for kw in kws]
            subject_filters.append(sa.or_(
                Academy.subjects.op("@>")(sa.type_coerce(json.dumps([s]), PGJSONB)),
                *name_kw_filters,
            ))
        filters.append(sa.or_(*subject_filters))
    if school_level:
        level_map = {"초등": "초등학교", "중등": "중학교", "고등": "고등학교"}
        mapped = level_map.get(school_level, school_level)
        filters.append(Academy.school_type.ilike(f"%{mapped}%"))

    # 후기 작성자 아이 정보 필터 (학교명 / 학년)
    # → 해당 조건의 학부모가 후기를 남긴 학원만 표시
    if reviewer_school or reviewer_grades:
        reviewer_filter_parts = []
        if reviewer_school:
            reviewer_filter_parts.append(User.school_name.ilike(f"%{reviewer_school}%"))
        if reviewer_grades:
            reviewer_filter_parts.append(User.grade.in_(reviewer_grades))
        reviewer_subq = (
            select(AcademyReview.academy_id)
            .join(User, User.id == AcademyReview.author_id)
            .where(*reviewer_filter_parts)
            .correlate(Academy)
        )
        filters.append(Academy.id.in_(reviewer_subq))

    result = await db.execute(
        select(Academy).where(*filters).order_by(
            # 숫자로 시작하는 이름은 맨 뒤
            sa.case((Academy.name.op("~")(r"^[0-9]"), 1), else_=0).asc(),
            # 후기 많은 것, 별점 높은 것 우선
            Academy.review_count.desc(),
            Academy.avg_rating.desc().nulls_last(),
            # 이름 가나다 순
            Academy.name.asc(),
        ).limit(10000)
    )
    academies = result.scalars().all()

    # DB에 결과 없을 때만 NEIS에서 추가 데이터 가져오기
    if not academies:
        neis_results = await neis_service.search_academies(
            name=name,
            region=region,
            subject=subjects[0] if subjects else None,
        )
        added = False
        for r in neis_results:
            neis_code = r.get("neis_academy_code")
            if neis_code:
                existing = await db.execute(
                    select(Academy).where(Academy.neis_academy_code == neis_code)
                )
                if existing.scalar_one_or_none():
                    continue
            else:
                existing = await db.execute(
                    select(Academy).where(Academy.name == r["name"], Academy.region == r.get("region"))
                )
                if existing.scalar_one_or_none():
                    continue
            academy_name = r["name"]
            detected = _detect_subjects_from_name(academy_name)
            academy = Academy(
                neis_academy_code=neis_code,
                name=academy_name,
                region=r.get("region"),
                address=r.get("address"),
                phone=r.get("phone"),
                subjects=detected,
                school_type=r.get("school_type"),
            )
            db.add(academy)
            added = True
        if added:
            await db.commit()

        result2 = await db.execute(
            select(Academy).where(*filters).order_by(
            # 숫자로 시작하는 이름은 맨 뒤
            sa.case((Academy.name.op("~")(r"^[0-9]"), 1), else_=0).asc(),
            # 후기 많은 것, 별점 높은 것 우선
            Academy.review_count.desc(),
            Academy.avg_rating.desc().nulls_last(),
            # 이름 가나다 순
            Academy.name.asc(),
        ).limit(10000)
        )
        academies = result2.scalars().all()

    return [AcademyResponse.model_validate(a) for a in academies]


async def patch_subjects(academy_id: int, subjects: list[str], db: AsyncSession) -> None:
    """관리자 전용: 학원 과목 목록 교체."""
    result = await db.execute(select(Academy).where(Academy.id == academy_id))
    academy = result.scalar_one_or_none()
    if not academy:
        raise ValueError("학원을 찾을 수 없습니다.")
    academy.subjects = subjects
    await db.commit()


async def get_academy(academy_id: int, db: AsyncSession) -> Optional[AcademyResponse]:
    result = await db.execute(select(Academy).where(Academy.id == academy_id))
    academy = result.scalar_one_or_none()
    if not academy:
        return None
    return AcademyResponse.model_validate(academy)


async def create_review(
    academy_id: int,
    user: User,
    req: AcademyReviewCreate,
    db: AsyncSession,
) -> AcademyReviewResponse:
    academy = (await db.execute(select(Academy).where(Academy.id == academy_id))).scalar_one_or_none()
    if not academy:
        raise ValueError("학원을 찾을 수 없습니다.")

    check_profanity(req.review_text, "후기")

    review = AcademyReview(
        academy_id=academy_id,
        author_id=user.id,
        subjects=req.subjects or [],
        teacher_styles=req.teacher_styles or [],
        homework_level=req.homework_level,
        score_improvement=req.score_improvement,
        review_text=req.review_text,
        rating=req.rating,
        nickname_type=req.nickname_type,
        is_anonymous=req.is_anonymous,
    )
    db.add(review)

    # 학원 통계 갱신
    academy.review_count += 1
    current_avg = float(academy.avg_rating or 0)
    prev_count = academy.review_count - 1
    new_avg = (current_avg * prev_count + req.rating) / academy.review_count
    academy.avg_rating = Decimal(str(round(new_avg, 2)))

    # 리뷰 과목 → academy.subjects에 추가 (중복 제외)
    if req.subjects:
        existing_subjects: list = list(academy.subjects or [])
        for s in req.subjects:
            if s not in existing_subjects:
                existing_subjects.append(s)
        academy.subjects = existing_subjects

    await db.commit()
    await db.refresh(review)

    author_display = None
    if not review.is_anonymous:
        author_display = user.nickname

    return AcademyReviewResponse(
        id=review.id,
        academy_id=review.academy_id,
        subjects=review.subjects or [],
        teacher_styles=review.teacher_styles or [],
        homework_level=review.homework_level,
        score_improvement=review.score_improvement,
        review_text=review.review_text,
        rating=review.rating,
        nickname_type=review.nickname_type,
        is_anonymous=review.is_anonymous,
        author_display_name=author_display,
        author_school_name=user.school_name or None,
        author_grade=user.grade,
        report_count=review.report_count,
        is_hidden=review.is_hidden,
        created_at=review.created_at,
    )


async def list_reviews(academy_id: int, db: AsyncSession) -> list[AcademyReviewResponse]:
    result = await db.execute(
        select(AcademyReview, User)
        .join(User, User.id == AcademyReview.author_id)
        .where(AcademyReview.academy_id == academy_id, AcademyReview.is_hidden == False)
        .order_by(AcademyReview.created_at.desc())
    )
    rows = result.all()
    out = []
    for review, author in rows:
        author_display = None
        if not review.is_anonymous:
            author_display = author.nickname
        out.append(AcademyReviewResponse(
            id=review.id,
            academy_id=review.academy_id,
            subjects=review.subjects or [],
            teacher_styles=review.teacher_styles or [],
            homework_level=review.homework_level,
            score_improvement=review.score_improvement,
            review_text=review.review_text,
            rating=review.rating,
            nickname_type=review.nickname_type,
            is_anonymous=review.is_anonymous,
            author_display_name=author_display,
            author_school_name=author.school_name or None,
            author_grade=author.grade,
            report_count=review.report_count,
            is_hidden=review.is_hidden,
            created_at=review.created_at,
        ))
    return out
