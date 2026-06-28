"""
양천구 학원 데이터를 NEIS API에서 전체 다운로드해 Supabase DB에 저장.
실행: python -m scripts.seed_yangcheon_academies
(backend/ 디렉터리에서)
"""
import asyncio
import json
import sys
from urllib.parse import quote

import httpx
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# ── 설정 ──────────────────────────────────────────────────────
NEIS_KEY = "07851452d93b43339b22dd8da632f8c9"
NEIS_URL = "https://open.neis.go.kr/hub/acaInsTiInfo"
EDU_CODE  = "B10"          # 서울특별시교육청
ZONE_NM   = "양천구"

DATABASE_URL = (
    "postgresql+asyncpg://postgres:UznK7%21U8%2BxcY%26%40g"
    "@db.buqysrebbuntpysfhcyx.supabase.co:5432/postgres"
)

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


def detect_subjects(name: str) -> list[str]:
    detected = []
    nl = name.lower()
    for subject, kws in _SUBJECT_KEYWORDS.items():
        if any(kw in name or kw.lower() in nl for kw in kws):
            detected.append(subject)
    return detected


async def fetch_all_from_neis() -> list[dict]:
    """NEIS API 페이지네이션으로 양천구 전체 학원 조회."""
    all_rows: list[dict] = []
    page = 1
    async with httpx.AsyncClient(timeout=20) as client:
        while True:
            params = {
                "KEY": NEIS_KEY,
                "Type": "json",
                "ATPT_OFCDC_SC_CODE": EDU_CODE,
                "ADMST_ZONE_NM": ZONE_NM,
                "pIndex": page,
                "pSize": 1000,
            }
            resp = await client.get(NEIS_URL, params=params)
            resp.raise_for_status()
            data = resp.json()

            if "RESULT" in data:
                code = data["RESULT"].get("CODE", "")
                if code == "INFO-200":
                    print(f"  페이지 {page}: 데이터 없음 (INFO-200), 종료")
                else:
                    print(f"  NEIS 오류: {data['RESULT']}")
                break

            rows = (
                data.get("acaInsTiInfo", [{}])[1].get("row", [])
                if "acaInsTiInfo" in data and len(data["acaInsTiInfo"]) > 1
                else []
            )
            print(f"  페이지 {page}: {len(rows)}건")
            all_rows.extend(rows)

            if len(rows) < 1000:
                break
            page += 1
            if page > 10:
                print("  10페이지 초과 → 중단")
                break

    return all_rows


async def main():
    print("=== 양천구 학원 NEIS 다운로드 시작 ===")
    rows = await fetch_all_from_neis()
    print(f"\nNEIS 총 {len(rows)}건 수신\n")

    if not rows:
        print("데이터 없음. 종료.")
        return

    engine = create_async_engine(DATABASE_URL, connect_args={"statement_cache_size": 0})
    Session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    inserted = 0
    updated  = 0
    skipped  = 0

    async with Session() as db:
        for row in rows:
            neis_code = row.get("ACA_INSTI_SC_CODE") or ""
            name      = row.get("ACA_NM", "").strip()
            region    = row.get("ADMST_ZONE_NM", "양천구").strip()
            address   = row.get("FA_RDNMA", "").strip()
            phone     = row.get("ACA_PONE_NO", "").strip()
            raw_subj  = row.get("LE_ORD_NM") or ""
            neis_subjs = [s.strip() for s in raw_subj.split(",") if s.strip()]
            detected   = detect_subjects(name)
            subjects   = list(dict.fromkeys(detected + [s for s in neis_subjs if s not in detected]))

            if not name:
                skipped += 1
                continue

            # neis_code로 중복 체크
            if neis_code:
                result = await db.execute(
                    text("SELECT id FROM academies WHERE neis_academy_code = :code"),
                    {"code": neis_code},
                )
                existing = result.fetchone()
                if existing:
                    # subjects가 비어있으면 업데이트
                    await db.execute(
                        text("""
                            UPDATE academies
                            SET subjects = COALESCE(
                                CASE WHEN subjects = '[]'::jsonb OR subjects IS NULL
                                     THEN :subjects::jsonb
                                     ELSE subjects
                                END,
                                :subjects::jsonb
                            ),
                            address = COALESCE(NULLIF(address, ''), :address),
                            phone   = COALESCE(NULLIF(phone, ''), :phone)
                            WHERE neis_academy_code = :code
                        """),
                        {
                            "code": neis_code,
                            "subjects": json.dumps(subjects, ensure_ascii=False),
                            "address": address,
                            "phone": phone,
                        },
                    )
                    updated += 1
                    continue

            # 이름+지역 중복 체크
            result = await db.execute(
                text("SELECT id FROM academies WHERE name = :name AND region = :region"),
                {"name": name, "region": region},
            )
            if result.fetchone():
                skipped += 1
                continue

            await db.execute(
                text("""
                    INSERT INTO academies
                        (neis_academy_code, name, region, address, phone, subjects,
                         review_count, avg_rating, is_b2b, created_at)
                    VALUES
                        (:code, :name, :region, :address, :phone, :subjects::jsonb,
                         0, NULL, false, NOW())
                """),
                {
                    "code": neis_code or None,
                    "name": name,
                    "region": region,
                    "address": address,
                    "phone": phone,
                    "subjects": json.dumps(subjects, ensure_ascii=False),
                },
            )
            inserted += 1

        await db.commit()

    await engine.dispose()

    print(f"\n완료!")
    print(f"  신규 삽입: {inserted}건")
    print(f"  기존 업데이트(subjects/address): {updated}건")
    print(f"  중복 스킵: {skipped}건")
    print(f"  합계: {inserted + updated + skipped} / {len(rows)}")


if __name__ == "__main__":
    asyncio.run(main())
