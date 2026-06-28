from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_optional_user
from app.db import get_service_db
from app.models.service_models import User
from app.schemas.academy import AcademyResponse, AcademyReviewCreate, AcademyReviewResponse
from app.services import academy_service

router = APIRouter(prefix="/academies", tags=["academies"])


@router.get("", response_model=list[AcademyResponse])
async def search_academies(
    name: Optional[str] = Query(None),
    region: Optional[str] = Query(None),
    subject: Optional[str] = Query(None),            # 단일 과목 (레거시)
    subjects: Optional[str] = Query(None),            # 복수 과목 콤마 구분 "수학,영어"
    school_level: Optional[str] = Query(None),        # 초등|중등|고등
    reviewer_school: Optional[str] = Query(None),     # 후기 작성자 아이 학교명
    reviewer_grades: Optional[str] = Query(None),     # 후기 작성자 아이 학년 콤마 구분 "1,2,3"
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_service_db),
):
    subject_list: Optional[list[str]] = None
    if subjects:
        subject_list = [s.strip() for s in subjects.split(",") if s.strip()]
    elif subject:
        subject_list = [subject]

    grade_list: Optional[list[int]] = None
    if reviewer_grades:
        grade_list = [int(g.strip()) for g in reviewer_grades.split(",") if g.strip().isdigit()]

    return await academy_service.search_academies(
        db,
        name=name,
        region=region,
        subjects=subject_list,
        school_level=school_level,
        reviewer_school=reviewer_school,
        reviewer_grades=grade_list,
    )


@router.get("/{academy_id}", response_model=AcademyResponse)
async def get_academy(
    academy_id: int,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_service_db),
):
    academy = await academy_service.get_academy(academy_id, db)
    if not academy:
        raise HTTPException(status_code=404, detail="학원을 찾을 수 없습니다.")
    return academy


@router.get("/{academy_id}/reviews", response_model=list[AcademyReviewResponse])
async def list_reviews(
    academy_id: int,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_service_db),
):
    return await academy_service.list_reviews(academy_id, db)


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
