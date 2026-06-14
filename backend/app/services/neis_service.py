"""
NEIS(교육부 나이스 오픈 API) 학교 검색 서비스.
API 키가 없으면 더미 데이터를 반환해 개발을 계속할 수 있게 한다.
sample key 사용 시 pSize 최대 5 고정 (NEIS 정책).
"""
import httpx
from typing import Optional

from app.core.config import settings
from app.schemas.school import SchoolSearchResult

SCHOOL_TYPE_MAP = {
    "초등학교": "elementary",
    "중학교": "middle",
    "고등학교": "high",
}

NEIS_ENDPOINT = "https://open.neis.go.kr/hub/schoolInfo"


async def search_schools(keyword: str, region_code: Optional[str] = None) -> list[SchoolSearchResult]:
    if not settings.NEIS_API_KEY:
        return _dummy_schools(keyword)

    is_sample = settings.NEIS_API_KEY.lower() == "sample"
    params = {
        "KEY": settings.NEIS_API_KEY,
        "Type": "json",
        "pIndex": 1,
        "pSize": 5 if is_sample else 30,
        "SCHUL_NM": keyword,
    }
    if region_code:
        params["ATPT_OFCDC_SC_CODE"] = region_code

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(NEIS_ENDPOINT, params=params)
            resp.raise_for_status()
            data = resp.json()
    except Exception:
        # API 호출 실패 시 더미 데이터 반환
        return _dummy_schools(keyword)

    # NEIS 오류 코드 처리
    if "RESULT" in data:
        return []

    rows = (
        data.get("schoolInfo", [{}])[1].get("row", [])
        if "schoolInfo" in data and len(data["schoolInfo"]) > 1
        else []
    )

    results = []
    for row in rows:
        school_type_kr = row.get("SCHUL_KND_SC_NM", "")
        school_type = SCHOOL_TYPE_MAP.get(school_type_kr)
        if not school_type:
            continue
        results.append(SchoolSearchResult(
            school_code=row.get("SD_SCHUL_CODE", ""),
            school_name=row.get("SCHUL_NM", ""),
            school_type=school_type,
            address=row.get("ORG_RDNMA", ""),
            region=row.get("LCTN_SC_NM", ""),
        ))
    return results


def _dummy_schools(keyword: str) -> list[SchoolSearchResult]:
    """NEIS API 키 없을 때 개발용 더미 데이터."""
    return [
        SchoolSearchResult(
            school_code="B100000219",
            school_name=f"{keyword}초등학교",
            school_type="elementary",
            address="서울특별시 강남구 테헤란로 1",
            region="서울특별시",
        ),
        SchoolSearchResult(
            school_code="B100000220",
            school_name=f"{keyword}중학교",
            school_type="middle",
            address="서울특별시 강남구 테헤란로 2",
            region="서울특별시",
        ),
        SchoolSearchResult(
            school_code="B100000221",
            school_name=f"{keyword}고등학교",
            school_type="high",
            address="서울특별시 강남구 테헤란로 3",
            region="서울특별시",
        ),
    ]
