"""
NEIS 학원 데이터 전국 동기화 서비스.

- 최초 실행(DB에 학원 100건 미만) 시 전국 17개 시도 전체 다운로드
- 이후 매주 1회 증분 업데이트 (NEIS upsert)
"""
import json
import logging
from datetime import datetime, timezone

import httpx
from sqlalchemy import select, func, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import SessionLocal
from app.models.service_models import Academy

logger = logging.getLogger(__name__)

NEIS_ACADEMY_URL = "https://open.neis.go.kr/hub/acaInsTiInfo"

# 전국 17개 시도교육청 코드
ALL_EDU_CODES: list[tuple[str, str]] = [
    ("B10", "서울"),
    ("C10", "부산"),
    ("D10", "대구"),
    ("E10", "인천"),
    ("F10", "광주"),
    ("G10", "대전"),
    ("H10", "울산"),
    ("I10", "세종"),
    ("J10", "경기"),
    ("K10", "강원"),
    ("M10", "충북"),
    ("N10", "충남"),
    ("P10", "전북"),
    ("Q10", "전남"),
    ("R10", "경북"),
    ("S10", "경남"),
    ("T10", "제주"),
]

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


def _detect_subjects(name: str) -> list[str]:
    nl = name.lower()
    return [
        subject
        for subject, kws in _SUBJECT_KEYWORDS.items()
        if any(kw in name or kw.lower() in nl for kw in kws)
    ]


async def _fetch_neis_page(
    client: httpx.AsyncClient,
    api_key: str,
    edu_code: str,
    page: int,
) -> list[dict]:
    params = {
        "KEY": api_key,
        "Type": "json",
        "ATPT_OFCDC_SC_CODE": edu_code,
        "pIndex": page,
        "pSize": 1000,
    }
    try:
        resp = await client.get(NEIS_ACADEMY_URL, params=params, timeout=20)
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        logger.warning("NEIS fetch error (edu=%s page=%d): %s", edu_code, page, e)
        return []

    if "RESULT" in data:
        return []  # INFO-200: 데이터 없음

    return (
        data.get("acaInsTiInfo", [{}])[1].get("row", [])
        if "acaInsTiInfo" in data and len(data["acaInsTiInfo"]) > 1
        else []
    )


async def _fetch_all_for_edu_code(
    client: httpx.AsyncClient, api_key: str, edu_code: str, label: str
) -> list[dict]:
    all_rows: list[dict] = []
    page = 1
    while True:
        rows = await _fetch_neis_page(client, api_key, edu_code, page)
        all_rows.extend(rows)
        logger.debug("  %s p%d: %d건", label, page, len(rows))
        if len(rows) < 1000:
            break
        page += 1
        if page > 20:
            logger.warning("%s: 20페이지 초과, 중단", label)
            break
    return all_rows


async def _upsert_rows(db: AsyncSession, rows: list[dict]) -> tuple[int, int]:
    """rows를 academies 테이블에 upsert. (inserted, updated) 반환."""
    inserted = updated = 0

    for row in rows:
        neis_code = (row.get("ACA_INSTI_SC_CODE") or "").strip() or None
        name      = (row.get("ACA_NM") or "").strip()
        region    = (row.get("ADMST_ZONE_NM") or "").strip()
        address   = (row.get("FA_RDNMA") or "").strip()
        phone     = (row.get("ACA_PONE_NO") or "").strip()
        raw_subj  = row.get("LE_ORD_NM") or ""
        neis_subjs = [s.strip() for s in raw_subj.split(",") if s.strip()]
        detected   = _detect_subjects(name)
        subjects   = list(dict.fromkeys(detected + [s for s in neis_subjs if s not in detected]))

        if not name:
            continue

        if neis_code:
            existing = (await db.execute(
                select(Academy).where(Academy.neis_academy_code == neis_code)
            )).scalar_one_or_none()

            if existing:
                # 이미 존재: subjects/address/phone 보완 업데이트
                changed = False
                if subjects and not existing.subjects:
                    existing.subjects = subjects
                    changed = True
                if address and not existing.address:
                    existing.address = address
                    changed = True
                if phone and not existing.phone:
                    existing.phone = phone
                    changed = True
                if changed:
                    updated += 1
                continue

        # 이름+지역 중복 체크
        dup = (await db.execute(
            select(Academy).where(Academy.name == name, Academy.region == region)
        )).scalar_one_or_none()
        if dup:
            continue

        db.add(Academy(
            neis_academy_code=neis_code,
            name=name,
            region=region,
            address=address,
            phone=phone,
            subjects=subjects,
            review_count=0,
            avg_rating=None,
            is_b2b=False,
        ))
        inserted += 1

    await db.commit()
    return inserted, updated


async def sync_all_academies(api_key: str, full: bool = False) -> None:
    """
    전국 학원 데이터 동기화.
    full=True  → 전국 17개 시도 전체
    full=False → 기존 DB에 있는 지역(region 목록)만 갱신
    """
    if not api_key or api_key.lower() == "sample":
        logger.info("NEIS API 키 없음 — 학원 동기화 건너뜀")
        return

    logger.info("학원 동기화 시작 (full=%s)", full)
    start = datetime.now(timezone.utc)
    total_inserted = total_updated = 0

    async with httpx.AsyncClient() as client:
        for edu_code, label in ALL_EDU_CODES:
            logger.info("[%s %s] NEIS 조회 중...", edu_code, label)
            rows = await _fetch_all_for_edu_code(client, api_key, edu_code, label)
            if not rows:
                logger.info("  → 데이터 없음")
                continue

            async with SessionLocal() as db:
                ins, upd = await _upsert_rows(db, rows)
                total_inserted += ins
                total_updated  += upd
                logger.info("  → %d건 수신 / 신규 %d / 갱신 %d", len(rows), ins, upd)

    elapsed = (datetime.now(timezone.utc) - start).total_seconds()
    logger.info(
        "학원 동기화 완료: 신규 %d건, 갱신 %d건, 소요 %.1fs",
        total_inserted, total_updated, elapsed,
    )


async def initial_sync_if_needed(api_key: str) -> None:
    """DB에 학원이 200건 미만이면 전국 전체 동기화 실행."""
    async with SessionLocal() as db:
        count = (await db.execute(select(func.count(Academy.id)))).scalar_one()

    if count < 200:
        logger.info("학원 DB %d건 → 전국 초기 동기화 시작", count)
        await sync_all_academies(api_key, full=True)
    else:
        logger.info("학원 DB %d건 — 초기 동기화 생략", count)
