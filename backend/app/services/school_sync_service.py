"""
NEIS 학교 데이터 전국 동기화 서비스.

- 최초 실행(DB 학교 1만 건 미만) 시 전국 17개 시도 전체 다운로드
- 이후 매주 1회 증분 upsert
"""
import logging
from datetime import datetime, timezone

import httpx
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import SessionLocal
from app.models.service_models import School

logger = logging.getLogger(__name__)

NEIS_SCHOOL_URL = "https://open.neis.go.kr/hub/schoolInfo"

SCHOOL_TYPE_MAP = {
    "초등학교": "elementary",
    "중학교": "middle",
    "고등학교": "high",
}

ALL_EDU_CODES: list[tuple[str, str]] = [
    ("B10", "서울"),   ("C10", "부산"),  ("D10", "대구"),
    ("E10", "인천"),   ("F10", "광주"),  ("G10", "대전"),
    ("H10", "울산"),   ("I10", "세종"),  ("J10", "경기"),
    ("K10", "강원"),   ("M10", "충북"),  ("N10", "충남"),
    ("P10", "전북"),   ("Q10", "전남"),  ("R10", "경북"),
    ("S10", "경남"),   ("T10", "제주"),
]


def _extract_district(address: str) -> str:
    parts = address.split()
    if not parts:
        return ""
    province = parts[0]
    if len(parts) < 2:
        return province
    second = parts[1]
    if any(province.endswith(s) for s in ("특별시", "광역시", "특별자치시")):
        return second
    if any(province.endswith(s) for s in ("도", "특별자치도")):
        if any(second.endswith(s) for s in ("시", "군")):
            return second
    return province


async def _fetch_schools_for_edu_code(
    client: httpx.AsyncClient, api_key: str, edu_code: str, label: str
) -> list[dict]:
    all_rows: list[dict] = []
    page = 1
    while True:
        params = {
            "KEY": api_key,
            "Type": "json",
            "ATPT_OFCDC_SC_CODE": edu_code,
            "pIndex": page,
            "pSize": 1000,
        }
        try:
            resp = await client.get(NEIS_SCHOOL_URL, params=params, timeout=20)
            resp.raise_for_status()
            data = resp.json()
        except Exception as e:
            logger.warning("학교 NEIS 오류 (%s p%d): %s", label, page, e)
            break

        if "RESULT" in data:
            break

        rows = (
            data.get("schoolInfo", [{}])[1].get("row", [])
            if "schoolInfo" in data and len(data["schoolInfo"]) > 1
            else []
        )
        all_rows.extend(rows)
        logger.debug("  %s p%d: %d건", label, page, len(rows))
        if len(rows) < 1000:
            break
        page += 1

    return all_rows


async def _upsert_schools(db: AsyncSession, rows: list[dict]) -> tuple[int, int]:
    inserted = updated = 0
    for row in rows:
        school_code = (row.get("SD_SCHUL_CODE") or "").strip()
        school_name = (row.get("SCHUL_NM") or "").strip()
        school_type_kr = row.get("SCHUL_KND_SC_NM", "")
        school_type = SCHOOL_TYPE_MAP.get(school_type_kr)
        address = (row.get("ORG_RDNMA") or "").strip()
        region = _extract_district(address)

        if not school_code or not school_name or not school_type:
            continue

        existing = (await db.execute(
            select(School).where(School.school_code == school_code)
        )).scalar_one_or_none()

        if existing:
            if existing.school_name != school_name or existing.address != address:
                existing.school_name = school_name
                existing.address = address
                existing.region = region
                existing.updated_at = datetime.now(timezone.utc)
                updated += 1
        else:
            db.add(School(
                school_code=school_code,
                school_name=school_name,
                school_type=school_type,
                address=address,
                region=region,
                updated_at=datetime.now(timezone.utc),
            ))
            inserted += 1

    await db.commit()
    return inserted, updated


async def sync_all_schools(api_key: str) -> None:
    if not api_key or api_key.lower() == "sample":
        logger.info("NEIS API 키 없음 — 학교 동기화 건너뜀")
        return

    logger.info("학교 동기화 시작 (전국 %d개 시도)", len(ALL_EDU_CODES))
    start = datetime.now(timezone.utc)
    total_inserted = total_updated = 0

    async with httpx.AsyncClient() as client:
        for edu_code, label in ALL_EDU_CODES:
            rows = await _fetch_schools_for_edu_code(client, api_key, edu_code, label)
            if not rows:
                continue
            async with SessionLocal() as db:
                ins, upd = await _upsert_schools(db, rows)
                total_inserted += ins
                total_updated += upd
                logger.info("[%s %s] %d건 → 신규 %d / 갱신 %d", edu_code, label, len(rows), ins, upd)

    elapsed = (datetime.now(timezone.utc) - start).total_seconds()
    logger.info("학교 동기화 완료: 신규 %d건, 갱신 %d건, %.1fs", total_inserted, total_updated, elapsed)


async def initial_school_sync_if_needed(api_key: str) -> None:
    """DB 학교가 1만 건 미만이면 전국 동기화 실행."""
    async with SessionLocal() as db:
        count = (await db.execute(select(func.count(School.id)))).scalar_one()

    if count < 10_000:
        logger.info("학교 DB %d건 → 전국 초기 동기화 시작", count)
        await sync_all_schools(api_key)
    else:
        logger.info("학교 DB %d건 — 초기 동기화 생략", count)
