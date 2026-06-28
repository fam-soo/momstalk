from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.models.service_models import School
from app.schemas.school import SchoolSearchResult
from app.services.neis_service import search_schools as neis_search_schools

router = APIRouter(prefix="/schools", tags=["schools"])


@router.get("/search", response_model=list[SchoolSearchResult])
async def search(
    q: Optional[str] = Query(None, min_length=2),
    keyword: Optional[str] = Query(None),
    region_code: Optional[str] = Query(None),
    school_type: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
):
    """학교 통합 검색 — DB 우선, 없으면 NEIS 실시간."""
    search_term = q or keyword

    # DB 조회
    stmt = select(School)
    conditions = []

    if search_term:
        from sqlalchemy import or_
        # 지역명 판단: 구/군/시 등으로 끝나고 짧으면 지역 검색
        _region_suffixes = ("구", "군", "시", "동", "읍", "면")
        if any(search_term.endswith(s) for s in _region_suffixes) and len(search_term) <= 6:
            conditions.append(School.region.ilike(f"%{search_term}%"))
        else:
            conditions.append(School.school_name.ilike(f"%{search_term}%"))

    if region_code:
        # NEIS 시도코드로 region 매핑 (B10→서울 등) — region 컬럼이 구 단위라 서울 전체는 address 검색
        from app.services.neis_service import NEIS_CODE_TO_REGION
        region_name = NEIS_CODE_TO_REGION.get(region_code, "")
        if region_name:
            conditions.append(School.address.ilike(f"%{region_name}%"))

    if school_type:
        conditions.append(School.school_type == school_type)

    if conditions:
        stmt = stmt.where(*conditions)

    stmt = stmt.order_by(School.school_name).limit(200)
    result = await db.execute(stmt)
    schools = result.scalars().all()

    if schools:
        return [
            SchoolSearchResult(
                school_code=s.school_code,
                school_name=s.school_name,
                school_type=s.school_type,
                address=s.address or "",
                region=s.region or "",
            )
            for s in schools
        ]

    # DB에 없으면 NEIS 실시간 fallback
    return await neis_search_schools(keyword=keyword, region_code=region_code, school_type=school_type, q=q)
