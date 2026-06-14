from fastapi import APIRouter, Query
from typing import Optional

from app.schemas.school import SchoolSearchResult
from app.services.neis_service import search_schools

router = APIRouter(prefix="/schools", tags=["schools"])


@router.get("/search", response_model=list[SchoolSearchResult])
async def search(
    keyword: str = Query(..., min_length=2, description="학교명 검색어 (2자 이상)"),
    region_code: Optional[str] = Query(None, description="시도 교육청 코드 (선택)"),
):
    """NEIS API로 학교 검색. API 키 없으면 더미 데이터 반환."""
    return await search_schools(keyword, region_code)
