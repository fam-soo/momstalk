import json
from collections import Counter
from datetime import datetime
from decimal import Decimal
from typing import Optional

import sqlalchemy as sa
from sqlalchemy import select, func
from sqlalchemy.dialects.postgresql import JSONB as PGJSONB
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.profanity import check_profanity
from app.models.service_models import Academy, AcademyReview, AcademyReviewUnlock, User
from app.schemas.academy import (
    AcademyReviewCreate,
    AcademyReviewResponse,
    AcademyResponse,
    AcademyReviewListResponse,
    AcademyUnlockQuota,
    AcademyMatchResult,
    QuotaInfo,
    RecommendationRequest,
    RecommendationResponse,
)
from app.services import neis_service

_REVIEW_PREVIEW_LEN = 40


# 한글 표기 ↔ 영문 표기 양방향 매핑
# 검색어가 어느 쪽으로 입력되어도 두 표기 모두 검색
_BRAND_ALIASES: list[tuple[str, ...]] = [
    # 수학·과학 전문
    ("씨엠에스", "CMS", "C.M.S"),
    ("시매쓰", "CMATH", "C-MATH", "씨매쓰"),
    ("와이즈만", "Wiseman", "WISEMAN"),
    ("에이매쓰", "AMATH", "A-MATH"),
    ("매쓰플렉스", "MathFlex", "MATHFLEX"),
    ("매쓰피아", "MathPia", "MATHPIA"),
    ("에이치엠에스", "HMS"),
    ("에스엠씨", "SMC"),

    # 영어 전문
    ("씨앤씨", "CNC", "C&C"),
    ("아발론", "Avalon", "AVALON"),
    ("에스엘피", "SLP"),
    ("청담어학원", "Chungdahm", "CDI", "청담"),
    ("윤선생", "Yoons", "YOONS"),
    ("에이프릴어학원", "April", "에이프릴", "APRIL"),
    ("파고다어학원", "Pagoda", "파고다", "PAGODA"),
    ("폴리어학원", "Poly", "POLY", "Koreapolyschool"),
    ("정상어학원", "JLS", "정상JLS"),
    ("최선어학원", "DYB", "최선DYB"),
    ("뮤엠영어", "Mu:m", "뮤엠", "MuM"),
    ("와이비엠", "YBM", "YBM어학원"),
    ("해커스어학원", "Hackers", "해커스"),
    ("랭콘", "Langcon", "랭콘잉글리쉬"),
    ("정철어학원", "JC"),
    ("에이원", "A1", "A-ONE", "AONE"),
    ("씨에스아이", "CSI"),
    ("에스아이에이", "SIA"),
    ("에이치에스씨", "HSC"),

    # 수학·사고력
    ("소마", "SOMA", "소마사고력수학"),
    ("생각하는황소", "황소수학"),
    ("깊은생각", "깊생"),
    ("해법수학", "Haebub", "e해법수학", "스마트해법"),
    ("쎈수학", "SSEN", "쎈수학러닝센터"),
    ("아담리즈", "Adamrise", "아담리즈수학"),
    ("파인만", "Feynman", "파인만학원"),

    # 독서논술·국어
    ("한우리", "Hanuri", "한우리독서논술"),
    ("씨앤에이논술", "C&A논술", "씨앤에이", "CNA논술"),
    ("플라톤", "Platon", "플라톤아카데미"),
    ("기탄", "Gitan", "기탄사고력"),
    ("국풍2000", "국풍"),

    # 종합·대형 프랜차이즈
    ("메가스터디", "MegaStudy", "MEGA"),
    ("이투스", "ETOOS", "E-TOOS", "E2US", "이투스247"),
    ("스카이에듀", "SkyEdu", "SKY EDU"),
    ("엠베스트", "M-Best", "MBEST"),
    ("대성학원", "Daesung", "대성마이맥"),
    ("시대인재", "SDJ", "Sidae"),
    ("종로학원", "Jongno", "Jongro"),
    ("명인학원", "Myungin"),
    ("토피아", "Topia", "토피아어학원"),
    ("한솔교육", "Hansol"),
    ("교원", "Kyowon", "KYOWON"),
    ("웅진씽크빅", "Woongjin", "ThinkBig"),
    ("눈높이", "Daekyo", "대교"),
    ("재능교육", "Jaenung", "JAENEUNG"),
    ("빨간펜", "RedPen", "RED PEN"),
    ("에듀플렉스", "EduPlex", "EDUPLEX"),
    ("에듀윌", "Eduwill"),
    ("공단기", "Gongdangi"),
    ("에이치에스", "HS"),
    ("피엠에스", "PMS"),
    ("와이즈", "Wise", "WISE"),

    # 코딩·로봇
    ("씨큐브코딩", "C3coding", "씨큐브"),
    ("잼코딩", "Jamcoding"),
    ("씨알에스", "CRS"),
    ("아이코딩", "iCoding", "I-CODING"),
    ("로보로보", "Robo", "ROBOROBO"),
    ("알고리짐", "Algorhythm"),
    ("스파르타코딩클럽", "Sparta Coding Club", "스파르타"),
    ("패스트캠퍼스", "FastCampus", "패캠"),

    # 예체능
    ("아트원", "Art1", "ART ONE"),
    ("에이알에스", "ARS"),
]

# 검색어 → 같은 그룹의 모든 표기 반환용 역방향 인덱스
_ALIAS_INDEX: dict[str, list[str]] = {}
for _group in _BRAND_ALIASES:
    for _term in _group:
        _ALIAS_INDEX[_term.lower()] = [t for t in _group if t != _term]


def _expand_name_aliases(name: str) -> list[str]:
    """검색어에 매핑된 다른 표기들을 반환 (자기 자신 제외)."""
    key = name.lower()
    # 완전일치 우선
    if key in _ALIAS_INDEX:
        return _ALIAS_INDEX[key]
    # 부분 포함 검사 — 검색어가 그룹 키워드 중 하나를 포함하면 그 그룹 전체 반환
    for alias_key, aliases in _ALIAS_INDEX.items():
        if alias_key in key or key in alias_key:
            return aliases
    return []


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
    regions: Optional[list[str]] = None,     # 복수 지역 필터 ["강남구", "양천구"]
    subjects: Optional[list[str]] = None,    # 복수 과목 필터
    school_level: Optional[str] = None,      # 초등|중등|고등
    reviewer_school: Optional[str] = None,   # 후기 작성자 아이의 학교명
    reviewer_grades: Optional[list[int]] = None,  # 후기 작성자 아이의 학년(들)
    learning_goals: Optional[list[str]] = None,  # 학습 목표 필터 (선행/심화/내신/수능/경시/영재)
    user: Optional[User] = None,             # 로그인 유저 — 학원별 열람(해금) 여부 표기용
) -> list[AcademyResponse]:
    """DB 우선 검색 → 결과 없으면 NEIS API 조회 후 DB 캐싱."""
    filters = []
    if name:
        aliases = _expand_name_aliases(name)
        if aliases:
            name_filters = [Academy.name.ilike(f"%{name}%")] + [
                Academy.name.ilike(f"%{a}%") for a in aliases
            ]
            filters.append(sa.or_(*name_filters))
        else:
            filters.append(Academy.name.ilike(f"%{name}%"))
    if regions:
        if len(regions) == 1:
            filters.append(Academy.region.ilike(f"%{regions[0]}%"))
        else:
            filters.append(sa.or_(*[Academy.region.ilike(f"%{r}%") for r in regions]))
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
    if learning_goals:
        # 선택한 학습 목표 중 하나라도 커리큘럼에 포함되면 표시 (OR 조건)
        filters.append(sa.or_(*[
            Academy.curriculum_focus.op("@>")(sa.type_coerce(json.dumps([g]), PGJSONB))
            for g in learning_goals
        ]))

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

    # 사용자 후기 수 / seed 보유 여부 서브쿼리
    user_review_subq = (
        select(func.count(AcademyReview.id))
        .where(AcademyReview.academy_id == Academy.id, AcademyReview.is_seed.isnot(True), AcademyReview.is_hidden.isnot(True))
        .correlate(Academy)
        .scalar_subquery()
    )
    has_seed_subq = (
        select(func.count(AcademyReview.id))
        .where(AcademyReview.academy_id == Academy.id, AcademyReview.is_seed.is_(True))
        .correlate(Academy)
        .scalar_subquery()
    )

    result = await db.execute(
        select(
            Academy,
            user_review_subq.label("user_review_count"),
            has_seed_subq.label("seed_count"),
        ).where(*filters).order_by(
            # 숫자로 시작하는 이름은 맨 뒤
            sa.case((Academy.name.op("~")(r"^[0-9]"), 1), else_=0).asc(),
            # 후기 많은 것, 별점 높은 것 우선
            Academy.review_count.desc(),
            Academy.avg_rating.desc().nulls_last(),
            # 이름 가나다 순
            Academy.name.asc(),
        ).limit(10000)
    )
    rows = result.all()
    academies = [(academy, urc, sc) for academy, urc, sc in rows]

    # DB에 결과 없을 때만 NEIS에서 추가 데이터 가져오기
    if not academies:
        neis_results = await neis_service.search_academies(
            name=name,
            region=regions[0] if regions else None,
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
            select(
                Academy,
                user_review_subq.label("user_review_count"),
                has_seed_subq.label("seed_count"),
            ).where(*filters).order_by(
                sa.case((Academy.name.op("~")(r"^[0-9]"), 1), else_=0).asc(),
                Academy.review_count.desc(),
                Academy.avg_rating.desc().nulls_last(),
                Academy.name.asc(),
            ).limit(10000)
        )
        academies = [(a, urc, sc) for a, urc, sc in result2.all()]

    unlocked_ids: set[int] = set()
    if user is not None:
        academy_ids = [a.id for a, _, _ in academies]
        if academy_ids:
            unlocked_ids = set((await db.execute(
                select(AcademyReviewUnlock.academy_id).where(
                    AcademyReviewUnlock.user_id == user.id,
                    AcademyReviewUnlock.academy_id.in_(academy_ids),
                )
            )).scalars().all())

    return [
        AcademyResponse.model_validate(a).model_copy(update={
            "user_review_count": urc or 0,
            "has_seed": (sc or 0) > 0,
            "is_unlocked": a.id in unlocked_ids,
        })
        for a, urc, sc in academies
    ]


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


async def update_academy_info(academy_id: int, req, db: AsyncSession) -> AcademyResponse:
    """일반 사용자(후기 작성 시)가 학원 기본 정보를 확인/수정 — 관리자 전용
    patch_subjects()와 달리 정회원 누구나 호출 가능. 보낸 필드만 덮어쓴다
    (None은 "변경 안 함"으로 취급 — 값을 지우려면 별도 관리자 기능 필요)."""
    academy = (await db.execute(select(Academy).where(Academy.id == academy_id))).scalar_one_or_none()
    if not academy:
        raise ValueError("학원을 찾을 수 없습니다.")

    if req.subjects is not None:
        academy.subjects = req.subjects
    if req.business_hours is not None:
        academy.business_hours = req.business_hours
    if req.shuttle_bus is not None:
        academy.shuttle_bus = req.shuttle_bus
    if req.avg_class_capacity is not None:
        academy.avg_class_capacity = req.avg_class_capacity
    if req.avg_tuition_10k_won is not None:
        academy.avg_tuition_10k_won = req.avg_tuition_10k_won
    if req.facilities is not None:
        academy.facilities = req.facilities

    await db.commit()
    await db.refresh(academy)
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

    active_child = user.active_child
    if active_child and active_child.school_type == "preschool" and academy.school_type in ("middle", "high"):
        raise ValueError("미취학 자녀로는 중·고등 전문 학원에 후기를 남길 수 없어요.")

    check_profanity(req.review_text, "후기")

    review = AcademyReview(
        academy_id=academy_id,
        author_id=user.id,
        subjects=req.subjects or [],
        teacher_styles=req.teacher_styles or [],
        homework_level=req.homework_level,
        score_improvement=req.score_improvement,
        student_traits=req.student_traits or [],
        score_level=req.score_level,
        feedback_frequency=req.feedback_frequency,
        score_change=req.score_change,
        recommend_to_similar=req.recommend_to_similar,
        review_text=req.review_text,
        rating=req.rating,
        nickname_type=req.nickname_type,
        nickname_snapshot=None if req.is_anonymous else user.nickname,
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

    # 유저 기여도 및 매너온도 갱신
    user.academy_review_count += 1
    user.manner_score += 10

    await db.commit()
    await db.refresh(review)

    from app.services.notification_service import notify_new_academy_review
    await notify_new_academy_review(db, review, academy)

    author_display = None
    if not review.is_anonymous:
        author_display = review.nickname_snapshot or user.nickname

    return AcademyReviewResponse(
        id=review.id,
        academy_id=review.academy_id,
        subjects=review.subjects or [],
        teacher_styles=review.teacher_styles or [],
        homework_level=review.homework_level,
        score_improvement=review.score_improvement,
        student_traits=review.student_traits or [],
        score_level=review.score_level,
        feedback_frequency=review.feedback_frequency,
        score_change=review.score_change,
        recommend_to_similar=review.recommend_to_similar,
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


async def update_review(
    academy_id: int,
    review_id: int,
    user: User,
    req,
    db: AsyncSession,
) -> AcademyReviewResponse:
    review = (await db.execute(
        select(AcademyReview).where(AcademyReview.id == review_id, AcademyReview.academy_id == academy_id)
    )).scalar_one_or_none()
    if not review:
        raise ValueError("후기를 찾을 수 없습니다.")
    if review.is_seed:
        raise PermissionError("이 후기는 수정할 수 없습니다.")
    if review.author_id != user.id:
        raise PermissionError("본인이 작성한 후기만 수정할 수 있습니다.")

    check_profanity(req.review_text, "후기")

    academy = (await db.execute(select(Academy).where(Academy.id == academy_id))).scalar_one_or_none()
    if academy and academy.review_count > 0:
        # 별점 변경분을 평균에 반영
        current_avg = float(academy.avg_rating or 0)
        total = current_avg * academy.review_count
        total = total - review.rating + req.rating
        academy.avg_rating = Decimal(str(round(total / academy.review_count, 2)))

    review.subjects = req.subjects or []
    review.teacher_styles = req.teacher_styles or []
    review.homework_level = req.homework_level
    review.score_improvement = req.score_improvement
    review.student_traits = req.student_traits or []
    review.score_level = req.score_level
    review.feedback_frequency = req.feedback_frequency
    review.score_change = req.score_change
    review.recommend_to_similar = req.recommend_to_similar
    review.review_text = req.review_text
    review.rating = req.rating
    review.nickname_type = req.nickname_type
    review.is_anonymous = req.is_anonymous
    # 익명 → 실명으로 바뀌는 시점에만 스냅샷을 새로 채운다 — 이미 스냅샷이
    # 있으면(원래도 실명 후기였던 경우) 최초 작성 시점 닉네임을 그대로 유지.
    if not review.is_anonymous and not review.nickname_snapshot:
        review.nickname_snapshot = user.nickname

    await db.commit()
    await db.refresh(review)

    author_display = None
    if not review.is_anonymous:
        author_display = review.nickname_snapshot or user.nickname

    return AcademyReviewResponse(
        id=review.id,
        academy_id=review.academy_id,
        subjects=review.subjects or [],
        teacher_styles=review.teacher_styles or [],
        homework_level=review.homework_level,
        score_improvement=review.score_improvement,
        student_traits=review.student_traits or [],
        score_level=review.score_level,
        feedback_frequency=review.feedback_frequency,
        score_change=review.score_change,
        recommend_to_similar=review.recommend_to_similar,
        review_text=review.review_text,
        rating=review.rating,
        nickname_type=review.nickname_type,
        is_anonymous=review.is_anonymous,
        is_own=True,
        author_display_name=author_display,
        author_school_name=user.school_name or None,
        author_grade=user.grade,
        report_count=review.report_count,
        is_hidden=review.is_hidden,
        created_at=review.created_at,
    )


def _academy_unlock_quota(user: User) -> Optional[int]:
    """사용자가 가림 처리 없이 전체 열람 가능한 "학원 개수" 반환. None = 무제한."""
    if user.is_admin:
        return None
    if user.member_grade == "lurker":
        return None  # lurker는 전체 허용
    count = user.academy_review_count
    if count >= 5:
        return None
    if count >= 1:
        return 5
    return 1


def _preview_text(text: str) -> str:
    """가림 처리 시 상단 한 줄만 노출하기 위한 미리보기 텍스트."""
    stripped = (text or "").strip()
    if not stripped:
        return ""
    first_line = stripped.splitlines()[0]
    if len(first_line) > _REVIEW_PREVIEW_LEN:
        return first_line[:_REVIEW_PREVIEW_LEN].rstrip() + "…"
    if first_line != stripped:
        return first_line + "…"
    return first_line


async def _unlocked_academy_count(user_id: int, db: AsyncSession) -> int:
    return (await db.execute(
        select(func.count(AcademyReviewUnlock.id)).where(AcademyReviewUnlock.user_id == user_id)
    )).scalar() or 0


async def _resolve_academy_access(user: User, academy_id: int, db: AsyncSession) -> tuple[bool, int, Optional[int]]:
    """(unlocked 여부, 해금한 학원 수, 해금 가능 총 개수(None=무제한)) 반환.

    쿼터가 남아있고 아직 이 학원을 해금한 적 없다면 이번 조회로 슬롯을 소비해
    해금 기록을 남긴다. 한 번 해금된 학원은 이후 계속 전체 열람 가능.
    """
    quota = _academy_unlock_quota(user)

    existing = (await db.execute(
        select(AcademyReviewUnlock).where(
            AcademyReviewUnlock.user_id == user.id,
            AcademyReviewUnlock.academy_id == academy_id,
        )
    )).scalar_one_or_none()

    if quota is None:
        # 무제한 열람 등급이어도 "이 학원을 열람했다"는 기록은 남겨서
        # 목록 화면에서 열람/미열람 구분(음영 처리)에 계속 활용한다.
        if not existing:
            db.add(AcademyReviewUnlock(user_id=user.id, academy_id=academy_id))
            await db.commit()
        return True, 0, None

    count = await _unlocked_academy_count(user.id, db)
    if existing:
        return True, count, quota
    if count < quota:
        db.add(AcademyReviewUnlock(user_id=user.id, academy_id=academy_id))
        await db.commit()
        return True, count + 1, quota
    return False, count, quota


async def get_unlock_quota_summary(user: User, db: AsyncSession) -> AcademyUnlockQuota:
    """후기 게시판 상단 배너용 — 특정 학원과 무관한 전역 해금 현황."""
    quota = _academy_unlock_quota(user)
    unlocked_count = 0 if quota is None else await _unlocked_academy_count(user.id, db)
    count = user.academy_review_count
    if quota is None:
        next_unlock_at = 0
    elif count >= 1:
        next_unlock_at = max(0, 5 - count)
    else:
        next_unlock_at = 1
    return AcademyUnlockQuota(
        unlocked_academy_count=unlocked_count,
        unlocked_academy_limit=quota,
        next_unlock_at=next_unlock_at,
        user_review_count=count,
    )


async def list_reviews(academy_id: int, user: User, db: AsyncSession, exclude_preschool: bool = False) -> AcademyReviewListResponse:
    result = await db.execute(
        select(AcademyReview, User)
        .outerjoin(User, User.id == AcademyReview.author_id)
        .where(AcademyReview.academy_id == academy_id, AcademyReview.is_hidden.isnot(True))
        .order_by(AcademyReview.is_seed.desc(), AcademyReview.created_at.asc())
    )
    rows = result.all()
    # seed 후기는 학원 소개용 — 사용자 후기 수 표시에서는 제외
    total = len([r for r, _ in rows if not (r.is_seed or False)])

    unlocked, unlocked_count, quota = await _resolve_academy_access(user, academy_id, db)

    count = user.academy_review_count
    if quota is None:
        next_unlock_at = 0
    elif count >= 1:
        next_unlock_at = max(0, 5 - count)
    else:
        next_unlock_at = 1

    out = []
    for review, author in rows:
        if exclude_preschool and author and author.active_child and author.active_child.school_type == "preschool":
            continue
        is_own = bool(author and author.id == user.id)
        # 학원이 잠겨 있으면 기본 소개(seed) + 사용자 후기 모두 가림 처리
        # 단, 본인이 작성한 후기는 잠금 대상에서 제외 (본인 글을 본인이 못 보는 문제 방지)
        view_limited = (not unlocked) and not is_own

        author_display = None
        school_name = None
        grade = None
        if author and not view_limited:
            if not review.is_anonymous:
                author_display = review.nickname_snapshot or author.nickname
            active = author.active_child
            school_name = (active.school_name if active else None) or author.school_name
            grade = (active.grade if active else None) or author.grade

        out.append(AcademyReviewResponse(
            id=review.id,
            academy_id=review.academy_id,
            subjects=[] if view_limited else (review.subjects or []),
            teacher_styles=[] if view_limited else (review.teacher_styles or []),
            homework_level=None if view_limited else review.homework_level,
            score_improvement=None if view_limited else review.score_improvement,
            student_traits=[] if view_limited else (review.student_traits or []),
            score_level=None if view_limited else review.score_level,
            feedback_frequency=None if view_limited else review.feedback_frequency,
            score_change=None if view_limited else review.score_change,
            recommend_to_similar=None if view_limited else review.recommend_to_similar,
            review_text=_preview_text(review.review_text) if view_limited else review.review_text,
            rating=review.rating,  # 별점은 항상 표시
            nickname_type=review.nickname_type,
            is_anonymous=review.is_anonymous,
            is_view_limited=view_limited,
            is_own=is_own,
            author_display_name=author_display,
            author_school_name=school_name,
            author_grade=grade,
            report_count=review.report_count or 0,
            is_hidden=review.is_hidden or False,
            is_seed=review.is_seed or False,
            created_at=review.created_at or datetime.utcnow(),
        ))

    return AcademyReviewListResponse(
        reviews=out,
        quota_info=QuotaInfo(
            total=total,
            academy_locked=not unlocked,
            unlocked_academy_count=unlocked_count,
            unlocked_academy_limit=quota,
            next_unlock_at=next_unlock_at,
            user_review_count=count,
        ),
    )


# ── 학원 추천받기 (규칙 기반 매칭) ─────────────────────────────
#
# 학습 목표/성향/수준을 5단계 설문으로 입력받아 학원별 매칭 점수(0~100%)를
# 계산한다. 후기 쪽 성향 태그(student_traits)나 학원 쪽 커리큘럼 태그
# (curriculum_focus)가 아직 거의 안 채워진 초기 단계를 전제로, "있는 신호만
# 가중 평균"하는 방식을 쓴다 — 신호가 없는 항목은 감점 없이 분모에서 빠진다.
# 데이터가 쌓일수록 자동으로 더 정교해진다.

_HOMEWORK_ORDER = ["없음", "적음", "보통", "많음", "매우 많음"]
_HOMEWORK_TOLERANCE_TO_LEVEL = {
    "30분": "적음", "60분": "보통", "90분": "많음", "120분": "매우 많음", "상관없음": None,
}
_MANAGEMENT_STYLE_HINTS: dict[str, list[str]] = {
    "자기주도형": ["학생 맞춤형이에요", "이해 중심으로 가르쳐요"],
    "가끔관리필요": ["숙제 피드백이 빨라요", "질문에 잘 답해줘요"],
    "밀착관리필요": ["숙제 피드백이 빨라요", "꼼꼼해요"],
}
_DESIRED_STYLE_HINTS: dict[str, list[str]] = {
    "자유로운 분위기": ["재미있어요", "친절해요"],
    "적당한 관리": ["학생 맞춤형이에요", "친절해요"],
    "철저한 관리": ["엄격해요", "숙제 피드백이 빨라요", "꼼꼼해요"],
}
_GOAL_TEACHER_STYLE_HINTS: dict[str, list[str]] = {
    "꼼꼼한 관리": ["꼼꼼해요", "숙제 피드백이 빨라요"],
    "아이와 잘 맞는 선생님": ["학생 맞춤형이에요", "친절해요"],
    "즐겁게 다니는 분위기": ["재미있어요", "친절해요"],
    "공부 습관": ["숙제 피드백이 빨라요", "반복 학습을 강조해요"],
}


def _constraint_excludes(constraint: str, academy: Academy, stats: dict) -> bool:
    """제약 조건 중 "명확히 어긋나면 목록에서 아예 제외"할 강한 조건만 하드 필터링."""
    if constraint == "경쟁이 심한 곳은 부담돼요":
        return bool(set(academy.curriculum_focus or []) & {"경시", "영재"})
    if constraint == "아이를 혼내는 분위기는 싫어요":
        return "엄격해요" in set(stats["teacher_styles"])
    if constraint == "너무 큰 학원은 부담돼요":
        return bool(academy.avg_class_capacity and float(academy.avg_class_capacity) > 30)
    if constraint == "숙제가 너무 많은 곳은 싫어요" and stats["homework_levels"]:
        common = Counter(stats["homework_levels"]).most_common(1)[0][0]
        return common == "매우 많음"
    return False


async def recommend_academies(user: User, req: RecommendationRequest, db: AsyncSession) -> RecommendationResponse:
    # regions(복수)가 오면 그걸 우선 사용 — 검색 필터처럼 기본 지역 + 추가 지역을
    # 선택할 수 있게 하기 전에는 region(단일)만 있어서 다른 지역 학원까지 섞여
    # 나오는 문제가 있었다(빈 문자열이면 필터 자체가 적용 안 됨).
    regions = [r for r in (req.regions or []) if r] or (
        [req.region] if req.region else
        ([user.active_child.region] if user.active_child and user.active_child.region else
         ([user.region] if user.region else []))
    )

    filters = []
    if regions:
        if len(regions) == 1:
            filters.append(Academy.region.ilike(f"%{regions[0]}%"))
        else:
            filters.append(sa.or_(*[Academy.region.ilike(f"%{r}%") for r in regions]))
    subject_filters = []
    for s in req.subjects:
        kws = _SUBJECT_KEYWORDS.get(s, [s])
        subject_filters.append(sa.or_(
            Academy.subjects.op("@>")(sa.type_coerce(json.dumps([s]), PGJSONB)),
            *[Academy.name.ilike(f"%{kw}%") for kw in kws],
        ))
    filters.append(sa.or_(*subject_filters))

    academies = (await db.execute(select(Academy).where(*filters).limit(300))).scalars().all()
    if not academies:
        return RecommendationResponse(results=[])

    academy_ids = [a.id for a in academies]
    # 실제 사용자 후기뿐 아니라 seed 후기(오늘학교 스크래핑을 AI가 요약한 것 —
    # summarize_reviews.py가 teacher_styles/homework_level/rating을 이미 채워둠)도
    # 매칭 신호로 활용한다. 다만 "리뷰가 적어 추정치" 신뢰도 캡은 실제 사용자
    # 후기 수(real_count) 기준으로 판단해 seed만 있는 학원을 과신하지 않는다.
    review_rows = (await db.execute(
        select(AcademyReview).where(
            AcademyReview.academy_id.in_(academy_ids),
            AcademyReview.is_hidden.isnot(True),
        )
    )).scalars().all()

    stats_by_academy: dict[int, dict] = {}
    for r in review_rows:
        s = stats_by_academy.setdefault(r.academy_id, {
            "count": 0, "real_count": 0, "seed_count": 0,
            "ratings": [], "homework_levels": [], "teacher_styles": [],
        })
        s["count"] += 1
        if r.is_seed:
            s["seed_count"] += 1
        else:
            s["real_count"] += 1
        s["ratings"].append(r.rating)
        if r.homework_level:
            s["homework_levels"].append(r.homework_level)
        if r.teacher_styles:
            s["teacher_styles"].extend(r.teacher_styles)

    empty_stats = {"count": 0, "real_count": 0, "seed_count": 0, "ratings": [], "homework_levels": [], "teacher_styles": []}
    results: list[AcademyMatchResult] = []

    for a in academies:
        stats = stats_by_academy.get(a.id, empty_stats)
        teacher_style_set = set(stats["teacher_styles"])
        curriculum = set(a.curriculum_focus or [])

        if any(_constraint_excludes(c, a, stats) for c in req.constraints):
            continue

        score = 0.0
        weight_used = 0.0
        reasons: list[str] = []

        # 0) 과목 일치 정도 — 10% (항상 반영). curriculum_focus/teacher_styles가
        # 채워진 학원이 각각 0.5%/12% 뿐이라(스크래핑 데이터 커버리지 한계),
        # 그 신호에만 의존하면 절대다수 학원이 30점 문턱을 못 넘고 폴백으로
        # 밀려난다 — SQL에서 이미 과목이 하나라도 일치해야 후보에 들어오므로,
        # "몇 개나 일치하는지"만이라도 항상 점수에 반영해 이 쏠림을 완화한다.
        if req.subjects:
            academy_subjects = set(a.subjects or [])
            subj_hits = sum(
                1 for s in req.subjects
                if s in academy_subjects or any(kw in (a.name or "") for kw in _SUBJECT_KEYWORDS.get(s, [s]))
            )
            comp = subj_hits / len(req.subjects)
            score += comp * 10
            weight_used += 10
            if comp >= 0.5:
                reasons.append("찾으시는 과목을 다뤄요")

        # 1) 수준(선행/심화/내신 등) 매칭 — 25%
        level_scores = []
        for subj in req.subjects:
            wanted = (req.subject_levels.get(subj) or {}).get("수준", "")
            if not wanted or not curriculum:
                continue
            if "선행" in wanted and "선행" in curriculum:
                level_scores.append(1.0)
            elif wanted == "학교 수준" and "내신" in curriculum:
                level_scores.append(0.8)
            elif curriculum:
                level_scores.append(0.4)
        if level_scores:
            comp = sum(level_scores) / len(level_scores)
            score += comp * 25
            weight_used += 25
            if comp >= 0.7:
                reasons.append("선택하신 학습 방향과 커리큘럼이 잘 맞아요")

        # 2) 숙제량 허용치와의 거리 — 15%
        if req.homework_tolerance and req.homework_tolerance != "상관없음" and stats["homework_levels"]:
            target = _HOMEWORK_TOLERANCE_TO_LEVEL.get(req.homework_tolerance)
            common = Counter(stats["homework_levels"]).most_common(1)[0][0]
            if target in _HOMEWORK_ORDER and common in _HOMEWORK_ORDER:
                dist = abs(_HOMEWORK_ORDER.index(target) - _HOMEWORK_ORDER.index(common))
                comp = max(0.0, 1 - dist / 4)
                score += comp * 15
                weight_used += 15
                if comp >= 0.75:
                    reasons.append("숙제량이 원하시는 수준과 비슷해요")

        # 3) 성향(관리 필요도/원하는 학원 스타일) - teacher_styles 매칭 — 25%
        trait_hits = trait_total = 0
        if req.management_need:
            trait_total += 1
            if teacher_style_set & set(_MANAGEMENT_STYLE_HINTS.get(req.management_need, [])):
                trait_hits += 1
        if req.desired_style:
            trait_total += 1
            if teacher_style_set & set(_DESIRED_STYLE_HINTS.get(req.desired_style, [])):
                trait_hits += 1
        if trait_total:
            comp = trait_hits / trait_total
            score += comp * 25
            weight_used += 25
            if comp > 0:
                reasons.append("선생님 스타일이 원하시는 성향과 맞아요")

        # 4) 이번에 기대하는 목표(최대 3개) 반영 — 20%
        if req.goals:
            goal_hits = 0
            avg_rating = sum(stats["ratings"]) / len(stats["ratings"]) if stats["ratings"] else 0
            for g in req.goals:
                if g == "성적 향상" and avg_rating >= 4.0:
                    goal_hits += 1
                elif g == "선행 진도" and "선행" in curriculum:
                    goal_hits += 1
                elif teacher_style_set & set(_GOAL_TEACHER_STYLE_HINTS.get(g, [])):
                    goal_hits += 1
            comp = goal_hits / len(req.goals)
            score += comp * 20
            weight_used += 20
            if comp >= 0.5:
                reasons.append("설정하신 목표와 관련된 후기가 있어요")

        # 4-1) 학습 목표(선행/심화/내신/수능/경시/영재) — 15%
        if req.learning_goals and curriculum:
            goal_hits = len(set(req.learning_goals) & curriculum)
            comp = goal_hits / len(req.learning_goals)
            score += comp * 15
            weight_used += 15
            if comp > 0:
                reasons.append("선택하신 학습 목표와 커리큘럼이 맞아요")

        # 5) 평점 — 15% (신호가 거의 없을 때도 최소한의 근거가 되도록)
        if stats["ratings"]:
            avg_rating = sum(stats["ratings"]) / len(stats["ratings"])
            comp = avg_rating / 5
            score += comp * 15
            weight_used += 15
            if avg_rating >= 4.2:
                reasons.append(f"후기 평점이 높아요 ({avg_rating:.1f}점)")

        final = round(score / weight_used * 100) if weight_used else 20
        if stats["count"] == 0:
            final = min(final, 60)
            reasons.append("아직 후기가 적어 추정치예요")
        elif stats["real_count"] == 0:
            # 실제 사용자 후기는 없고 AI 요약(seed) 후기만 있는 경우 —
            # 신호는 있지만 우리 서비스 사용자 검증은 아직 안 된 상태라 완전 신뢰는 캡.
            final = min(final, 80)
            reasons.append("AI 요약 후기 기반 추정치예요")
        final = max(0, min(100, final))

        if final < 30:
            continue  # 완전 무관으로 판단 — 결과에서 제외

        results.append(AcademyMatchResult(
            academy=AcademyResponse.model_validate(a).model_copy(update={
                "user_review_count": stats["count"],
                "avg_rating": (sum(stats["ratings"]) / len(stats["ratings"])) if stats["ratings"] else (float(a.avg_rating) if a.avg_rating else None),
            }),
            match_score=final,
            match_reasons=reasons,
        ))

    results.sort(key=lambda r: r.match_score, reverse=True)

    if results:
        return RecommendationResponse(results=results[:30])

    # 조건에 맞는 학원이 하나도 없을 때 — 완전히 빈 화면 대신, 과목만 일치하는
    # 학원을 평점순으로 참고용으로 보여준다("매칭은 안 됐지만 후기 참고해서
    # 직접 골라보시라"는 의도). match_score는 실제 매칭도가 아니라 참고 순위.
    fallback = []
    for a in academies:
        stats = stats_by_academy.get(a.id, empty_stats)
        avg_rating = (sum(stats["ratings"]) / len(stats["ratings"])) if stats["ratings"] else (float(a.avg_rating) if a.avg_rating else 0.0)
        fallback.append((avg_rating, stats["count"], a, stats))

    fallback.sort(key=lambda t: (t[0], t[1]), reverse=True)

    fallback_results = [
        AcademyMatchResult(
            academy=AcademyResponse.model_validate(a).model_copy(update={
                "user_review_count": stats["count"],
                "avg_rating": avg_rating if avg_rating else None,
            }),
            match_score=0,
            match_reasons=["조건에 정확히 맞는 학원은 없지만, 같은 과목 학원 중 평점이 높아요"] if avg_rating else ["조건에 정확히 맞는 학원은 없지만, 같은 과목을 가르쳐요"],
        )
        for avg_rating, _count, a, stats in fallback[:30]
    ]
    return RecommendationResponse(results=fallback_results, is_fallback=True)
