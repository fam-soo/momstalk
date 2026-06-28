from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
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
    subject: Optional[str] = Query(None),
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_service_db),
):
    return await academy_service.search_academies(db, name=name, region=region, subject=subject)


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
