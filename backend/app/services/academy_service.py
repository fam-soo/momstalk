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
    subject: Optional[str] = None,
) -> list[AcademyResponse]:
    """DB 우선 검색 → 결과 없으면 NEIS API 조회 후 DB 캐싱.

    이름 검색 시 region 필터 미적용 (전국 검색) — region은 지역 목록 조회에만 사용.
    """
    filters = []
    if name:
        # 이름으로 검색할 때는 지역 제한 없이 전체에서 LIKE 검색
        filters.append(Academy.name.ilike(f"%{name}%"))
    elif region:
        # 이름 없이 지역만 있을 때만 region 필터 적용
        filters.append(Academy.region.ilike(f"%{region}%"))
    if subject:
        # JSONB 배열 포함 검사 (@>) — cast(Text) ilike는 한글 유니코드 escape로 매칭 실패
        filters.append(Academy.subjects.op("@>")(sa.type_coerce(json.dumps([subject]), PGJSONB)))

    result = await db.execute(
        select(Academy).where(*filters).order_by(Academy.review_count.desc()).limit(50)
    )
    academies = result.scalars().all()

    if not academies:
        # NEIS API 조회 후 DB 저장 — 이름 검색 시 region 없이 전국 조회
        neis_results = await neis_service.search_academies(
            name=name,
            region=None if name else region,  # 이름 검색 시 region 제한 해제
            subject=subject,
        )
        for r in neis_results:
            neis_code = r.get("neis_academy_code")
            if neis_code:
                existing = await db.execute(
                    select(Academy).where(Academy.neis_academy_code == neis_code)
                )
                if existing.scalar_one_or_none():
                    continue
            else:
                # neis_code 없는 경우 이름+지역으로 중복 체크
                existing = await db.execute(
                    select(Academy).where(Academy.name == r["name"], Academy.region == r.get("region"))
                )
                if existing.scalar_one_or_none():
                    continue
            academy_name = r["name"]
            neis_subjects = r.get("subjects") or []
            detected = _detect_subjects_from_name(academy_name)
            merged_subjects = list(dict.fromkeys(detected + [s for s in neis_subjects if s not in detected]))
            academy = Academy(
                neis_academy_code=neis_code,
                name=academy_name,
                region=r.get("region"),
                address=r.get("address"),
                phone=r.get("phone"),
                subjects=merged_subjects if merged_subjects else neis_subjects,
                school_type=r.get("school_type"),
            )
            db.add(academy)
        await db.commit()

        result2 = await db.execute(
            select(Academy).where(*filters).order_by(Academy.review_count.desc()).limit(50)
        )
        academies = result2.scalars().all()

    return [AcademyResponse.model_validate(a) for a in academies]


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
        subject=req.subject,
        teacher_style=req.teacher_style,
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
    if req.subject:
        existing_subjects: list = list(academy.subjects or [])
        if req.subject not in existing_subjects:
            existing_subjects.append(req.subject)
            academy.subjects = existing_subjects

    await db.commit()
    await db.refresh(review)

    author_display = None
    if not review.is_anonymous:
        if review.nickname_type == "certified":
            author_display = user.certified_nickname or user.nickname
        else:
            author_display = user.nickname

    return AcademyReviewResponse(
        id=review.id,
        academy_id=review.academy_id,
        subject=review.subject,
        teacher_style=review.teacher_style,
        homework_level=review.homework_level,
        score_improvement=review.score_improvement,
        review_text=review.review_text,
        rating=review.rating,
        nickname_type=review.nickname_type,
        is_anonymous=review.is_anonymous,
        author_display_name=author_display,
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
            if review.nickname_type == "certified":
                author_display = author.certified_nickname or author.nickname
            else:
                author_display = author.nickname
        out.append(AcademyReviewResponse(
            id=review.id,
            academy_id=review.academy_id,
            subject=review.subject,
            teacher_style=review.teacher_style,
            homework_level=review.homework_level,
            score_improvement=review.score_improvement,
            review_text=review.review_text,
            rating=review.rating,
            nickname_type=review.nickname_type,
            is_anonymous=review.is_anonymous,
            author_display_name=author_display,
            report_count=review.report_count,
            is_hidden=review.is_hidden,
            created_at=review.created_at,
        ))
    return out
