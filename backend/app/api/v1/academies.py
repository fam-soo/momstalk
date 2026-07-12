from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_optional_user
from app.core.rate_limit import RateLimit
from app.db import get_service_db
from app.models.service_models import User
from app.schemas.academy import (
    AcademyResponse,
    AcademyReviewCreate,
    AcademyReviewResponse,
    AcademyReviewListResponse,
    AcademyReviewUpdate,
    AcademyInfoUpdate,
    AcademyUnlockQuota,
    RecommendationRequest,
    RecommendationResponse,
)
from app.services import academy_service

router = APIRouter(prefix="/academies", tags=["academies"])


@router.get("/review-quota", response_model=AcademyUnlockQuota)
async def get_review_quota(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """후기 게시판 상단 배너용 — 가림 처리 없이 열람 가능한 학원 개수 현황."""
    return await academy_service.get_unlock_quota_summary(user, db)


@router.post("/recommendations", response_model=RecommendationResponse)
async def recommend_academies(
    req: RecommendationRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """학원 추천받기 — 5단계 설문 기반 규칙 매칭. 완전 무관한 학원은 결과에서 제외."""
    await RateLimit.academy_search(request)
    try:
        return await academy_service.recommend_academies(user, req, db)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("", response_model=list[AcademyResponse])
async def search_academies(
    request: Request,
    name: Optional[str] = Query(None),
    region: Optional[str] = Query(None),          # 단일 또는 콤마 구분 복수 "강남구,양천구"
    subject: Optional[str] = Query(None),            # 단일 과목 (레거시)
    subjects: Optional[str] = Query(None),            # 복수 과목 콤마 구분 "수학,영어"
    school_level: Optional[str] = Query(None),        # 초등|중등|고등
    reviewer_school: Optional[str] = Query(None),     # 후기 작성자 아이 학교명
    reviewer_grades: Optional[str] = Query(None),     # 후기 작성자 아이 학년 콤마 구분 "1,2,3"
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_service_db),
):
    await RateLimit.academy_search(request)
    subject_list: Optional[list[str]] = None
    if subjects:
        subject_list = [s.strip() for s in subjects.split(",") if s.strip()]
    elif subject:
        subject_list = [subject]

    grade_list: Optional[list[int]] = None
    if reviewer_grades:
        grade_list = [int(g.strip()) for g in reviewer_grades.split(",") if g.strip().isdigit()]

    region_list: Optional[list[str]] = None
    if region:
        region_list = [r.strip() for r in region.split(",") if r.strip()]

    return await academy_service.search_academies(
        db,
        name=name,
        regions=region_list,
        subjects=subject_list,
        school_level=school_level,
        reviewer_school=reviewer_school,
        reviewer_grades=grade_list,
        user=user,
    )


@router.get("/{academy_id}", response_model=AcademyResponse)
async def get_academy(
    academy_id: int,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_service_db),
):
    await RateLimit.academy_detail(request)
    academy = await academy_service.get_academy(academy_id, db)
    if not academy:
        raise HTTPException(status_code=404, detail="학원을 찾을 수 없습니다.")
    return academy


@router.patch("/{academy_id}/info", response_model=AcademyResponse)
async def update_academy_info(
    academy_id: int,
    req: AcademyInfoUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """정회원이 후기 작성 시점에 학원 기본 정보(과목/영업시간/셔틀버스/정원/학원비)를
    확인하고 틀린 부분을 고칠 수 있도록 하는 크라우드소싱 보정. 관리자 전용
    /subjects 엔드포인트와 달리 일반 회원도 호출 가능."""
    try:
        return await academy_service.update_academy_info(academy_id, req, db)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.get("/{academy_id}/kakao-place")
async def get_kakao_place(
    academy_id: int,
    db: AsyncSession = Depends(get_service_db),
):
    """카카오 Local API로 학원의 카카오맵 장소 URL 조회."""
    import httpx
    from app.core.config import settings
    academy = await academy_service.get_academy(academy_id, db)
    if not academy:
        raise HTTPException(status_code=404, detail="학원을 찾을 수 없습니다.")

    api_key = settings.KAKAO_CLIENT_ID.strip()
    if not api_key:
        raise HTTPException(status_code=503, detail="카카오 API 키 미설정")

    query = academy.name
    if academy.address:
        query = f"{academy.name} {academy.address[:10]}"

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(
                "https://dapi.kakao.com/v2/local/search/keyword.json",
                params={"query": query, "category_group_code": "AC5", "size": 5},
                headers={"Authorization": f"KakaoAK {api_key}"},
            )
            resp.raise_for_status()
            data = resp.json()
    except Exception:
        raise HTTPException(status_code=503, detail="카카오 API 호출 실패")

    documents = data.get("documents", [])
    if not documents:
        return {"place_url": None, "found": False}

    # 학원명이 가장 유사한 결과 우선
    for doc in documents:
        if academy.name in doc.get("place_name", "") or doc.get("place_name", "") in academy.name:
            return {"place_url": doc["place_url"], "place_name": doc["place_name"], "found": True}

    first = documents[0]
    return {"place_url": first["place_url"], "place_name": first["place_name"], "found": True}


@router.get("/{academy_id}/reviews", response_model=AcademyReviewListResponse)
async def list_reviews(
    academy_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    await RateLimit.academy_detail(request)
    return await academy_service.list_reviews(academy_id, user, db)


@router.post("/{academy_id}/reviews", response_model=AcademyReviewResponse, status_code=201)
async def create_review(
    academy_id: int,
    req: AcademyReviewCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    try:
        return await academy_service.create_review(academy_id, user, req, db)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.patch("/{academy_id}/reviews/{review_id}", response_model=AcademyReviewResponse)
async def update_review(
    academy_id: int,
    review_id: int,
    req: AcademyReviewUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    try:
        return await academy_service.update_review(academy_id, review_id, user, req, db)
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


class AdminSubjectPatch(BaseModel):
    subjects: list[str]


@router.patch("/{academy_id}/subjects")
async def admin_patch_subjects(
    academy_id: int,
    req: AdminSubjectPatch,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """관리자 전용: 학원 과목 목록 직접 수정."""
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="관리자만 사용할 수 있습니다.")
    try:
        await academy_service.patch_subjects(academy_id, req.subjects, db)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return {"ok": True}
