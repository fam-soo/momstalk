from fastapi import APIRouter, Query
from typing import Optional

from app.schemas.school import SchoolSearchResult
from app.services.neis_service import search_schools

router = APIRouter(prefix="/schools", tags=["schools"])


@router.get("/search", response_model=list[SchoolSearchResult])
async def search(
    q: Optional[str] = Query(None, min_length=2, description="통합 검색어 — 학교명('행복초') 또는 지역명('강남구') 모두 가능"),
    keyword: Optional[str] = Query(None, description="학교명 검색어 (하위 호환)"),
    region_code: Optional[str] = Query(None, description="NEIS 시도 교육청 코드"),
    school_type: Optional[str] = Query(None, description="elementary / middle / high"),
):
    """학교 통합 검색 (NEIS API).

    - q="행복초" → 전국 학교명 검색
    - q="강남구" → 강남구 소재 학교 목록 (지역명 자동 감지)
    - q="해운대구" + school_type="elementary" → 해운대구 초등학교만
    - region_code + school_type → 해당 시도 전체 목록 (기존 동작 유지)
    """
    return await search_schools(keyword=keyword, region_code=region_code, school_type=school_type, q=q)
