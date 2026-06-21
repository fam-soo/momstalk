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

SCHOOL_TYPE_KR = {v: k for k, v in SCHOOL_TYPE_MAP.items()}

NEIS_ENDPOINT = "https://open.neis.go.kr/hub/schoolInfo"

NEIS_CODE_TO_REGION = {
    "B10": "서울특별시", "C10": "부산광역시", "D10": "대구광역시",
    "E10": "인천광역시", "F10": "광주광역시", "G10": "대전광역시",
    "H10": "울산광역시", "I10": "세종특별자치시", "J10": "경기도",
    "K10": "강원특별자치도", "M10": "충청북도", "N10": "충청남도",
    "P10": "전북특별자치도", "Q10": "전라남도", "R10": "경상북도",
    "S10": "경상남도", "T10": "제주특별자치도",
}

# 주요 구/군 → 시도 NEIS 코드 (지역명 검색 시 사용)
_DISTRICT_TO_NEIS_CODE: dict[str, str] = {
    # 서울
    "강남구": "B10", "강동구": "B10", "강북구": "B10", "강서구": "B10",
    "관악구": "B10", "광진구": "B10", "구로구": "B10", "금천구": "B10",
    "노원구": "B10", "도봉구": "B10", "동대문구": "B10", "동작구": "B10",
    "마포구": "B10", "서대문구": "B10", "서초구": "B10", "성동구": "B10",
    "성북구": "B10", "송파구": "B10", "양천구": "B10", "영등포구": "B10",
    "용산구": "B10", "은평구": "B10", "종로구": "B10", "중구": "B10", "중랑구": "B10",
    # 경기
    "수원시": "J10", "성남시": "J10", "고양시": "J10", "용인시": "J10",
    "부천시": "J10", "안산시": "J10", "안양시": "J10", "남양주시": "J10",
    "화성시": "J10", "평택시": "J10", "의정부시": "J10", "시흥시": "J10",
    "파주시": "J10", "광명시": "J10", "김포시": "J10", "군포시": "J10",
    "이천시": "J10", "양주시": "J10", "오산시": "J10", "구리시": "J10",
    # 부산
    "해운대구": "C10", "부산진구": "C10", "동래구": "C10", "남구": "C10",
    "북구": "C10", "강서구 ": "C10", "수영구": "C10", "사상구": "C10",
    # 인천
    "연수구": "E10", "남동구": "E10", "부평구": "E10", "계양구": "E10",
    "미추홀구": "E10", "서구": "E10", "동구": "E10",
    # 대구
    "달서구": "D10", "수성구": "D10", "북구 ": "D10", "동구 ": "D10",
}

# 지역명 쿼리로 판단하는 접미사
_REGION_SUFFIXES = ("구", "군", "시", "동", "읍", "면")


def _is_region_query(q: str) -> bool:
    """검색어가 지역명(구/군/시 등)인지 판단."""
    return any(q.endswith(s) for s in _REGION_SUFFIXES) and len(q) <= 6


def _extract_district(address: str) -> str:
    """NEIS ORG_RDNMA 주소에서 지역 단위를 추출.

    특별시/광역시/특별자치시 → 구 단위   "서울특별시 강남구 ..." → "강남구"
    도/특별자치도           → 시/군 단위 "경기도 안양시 ..."    → "안양시"
    세종특별자치시          → 시 자체     "세종특별자치시 ..."    → "세종특별자치시"
    """
    parts = address.split()
    if not parts:
        return address
    province = parts[0]
    if len(parts) < 2:
        return province

    second = parts[1]
    # 특별시/광역시/특별자치시: 두 번째 토큰이 구 단위
    if any(province.endswith(s) for s in ("특별시", "광역시", "특별자치시")):
        return second  # e.g. "강남구", "해운대구"
    # 도/특별자치도: 두 번째 토큰이 시/군 단위
    if any(province.endswith(s) for s in ("도", "특별자치도")):
        if any(second.endswith(s) for s in ("시", "군")):
            return second  # e.g. "안양시", "가평군", "제주시"
    return province


async def search_schools(
    keyword: Optional[str] = None,
    region_code: Optional[str] = None,
    school_type: Optional[str] = None,
    q: Optional[str] = None,
) -> list[SchoolSearchResult]:
    """통합 학교 검색.

    q 파라미터 우선. q가 지역명이면 region_code를 자동 추론 후 주소 필터 적용.
    """
    district_filter: Optional[str] = None

    if q:
        if _is_region_query(q):
            # 지역명 검색: NEIS 코드 추론 → 주소 필터
            district_filter = q
            inferred_code = _DISTRICT_TO_NEIS_CODE.get(q)
            if inferred_code and not region_code:
                region_code = inferred_code
            keyword = None  # 학교명 필터 해제
        else:
            keyword = q  # 학교명 검색으로 처리

    if not settings.NEIS_API_KEY:
        return _dummy_schools(keyword, region_code, school_type, district_filter)

    is_sample = settings.NEIS_API_KEY.lower() == "sample"
    p_size = 5 if is_sample else (100 if not keyword else 30)

    params = {
        "KEY": settings.NEIS_API_KEY,
        "Type": "json",
        "pIndex": 1,
        "pSize": p_size,
    }
    if keyword:
        params["SCHUL_NM"] = keyword
    if region_code:
        params["ATPT_OFCDC_SC_CODE"] = region_code
    if school_type and school_type in SCHOOL_TYPE_KR:
        params["SCHUL_KND_SC_NM"] = SCHOOL_TYPE_KR[school_type]

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(NEIS_ENDPOINT, params=params)
            resp.raise_for_status()
            data = resp.json()
    except Exception:
        return _dummy_schools(keyword, region_code, school_type, district_filter)

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
        st = SCHOOL_TYPE_MAP.get(school_type_kr)
        if not st:
            continue
        address = row.get("ORG_RDNMA", "")
        # 지역 필터: 주소에 district_filter가 포함돼야 함
        if district_filter and district_filter not in address:
            continue
        results.append(SchoolSearchResult(
            school_code=row.get("SD_SCHUL_CODE", ""),
            school_name=row.get("SCHUL_NM", ""),
            school_type=st,
            address=address,
            region=_extract_district(address),
        ))
    return results


def _dummy_schools(
    keyword: Optional[str],
    region_code: Optional[str],
    school_type: Optional[str],
    district_filter: Optional[str] = None,
) -> list[SchoolSearchResult]:
    """NEIS API 키 없을 때 개발용 더미 데이터."""
    region_label = NEIS_CODE_TO_REGION.get(region_code or "", "서울특별시")
    district = district_filter or (region_label[:3] if not keyword else "")
    prefix = keyword or district or region_label[:2]

    types = [school_type] if school_type else ["elementary", "middle", "high"]
    results = []
    for t in types:
        type_kr = SCHOOL_TYPE_KR[t]
        count = 8 if not keyword else 3
        for i in range(1, count + 1):
            addr = f"{region_label} {district or '중구'} 테헤란로 {i * 10}"
            results.append(SchoolSearchResult(
                school_code=f"DUMMY{t[:3].upper()}{i:03d}",
                school_name=f"{prefix}{i}{type_kr}",
                school_type=t,
                address=addr,
                region=district or region_label[:3],
            ))
    return results
