"""서버 사이드 금칙어 필터.

금칙어는 세 가지 경로로 관리됩니다:
  1. 코드 내 기본 목록 (_DEFAULT_WORDS)
  2. 환경변수 PROFANITY_WORDS (쉼표 구분)
  3. DB profanity_words 테이블 (관리자 대시보드에서 실시간 관리)

DB 목록은 60초 캐시로 유지되어 매 요청마다 DB를 조회하지 않습니다.
"""
import os
import re
import time
from typing import Optional

_DEFAULT_WORDS: list[str] = [
    # ── 한국어 욕설 ──────────────────────────────────
    "씨발", "개새끼", "병신", "지랄", "좆", "보지", "자지",
    "미친놈", "미친년", "꺼져", "죽어", "죽여",
    "씹", "썅", "니미", "애미", "애비", "느금마", "호로새끼",
    "아가리", "대가리", "좆밥", "옘병", "쌍년", "썅년",
    "미친색기", "미친새끼", "뒤져라", "뒈져라",

    # ── 초성 욕설 ────────────────────────────────────
    "ㅅㅂ", "ㅆㅂ", "ㅂㅅ", "ㅃㅅ", "ㅈㄹ", "ㅈㄲ",
    "ㄱㅅㄲ", "ㅁㅊㄴ", "ㄷㅊ", "ㅇㅁ", "ㅇㅂ", "ㅈㄴ",

    # ── 영어 욕설 (IGNORECASE 적용) ──────────────────
    "fuck", "shit", "bitch", "asshole", "cunt", "slut", "whore",
    "retard", "motherfucker", "bullshit",

    # ── 혐오·분쟁 유발 (학부모 커뮤니티 특성) ─────────
    "맘충", "애비충", "잼민이", "급식충", "틀딱",
    "한남", "한녀", "김치녀", "된장녀", "짱깨", "조센징",
]

# "시발"은 "시발점·시발역" 오탐지 방지를 위해 부정 전방탐색 적용
_CONTEXT_PATTERNS: list[re.Pattern] = [
    re.compile(r"시발(?!점|역|역사|역할)", re.IGNORECASE),
]

_env_extra = [w.strip() for w in os.environ.get("PROFANITY_WORDS", "").split(",") if w.strip()]

# DB 캐시
_db_words_cache: list[str] = []
_db_cache_ts: float = 0.0
_DB_CACHE_TTL = 60.0  # 60초


def _get_db_words() -> list[str]:
    """profanity_words 테이블에서 금칙어 로드 (60초 캐시)."""
    global _db_words_cache, _db_cache_ts
    now = time.monotonic()
    if now - _db_cache_ts < _DB_CACHE_TTL:
        return _db_words_cache
    try:
        from sqlalchemy import create_engine, text
        db_url = os.environ.get("DATABASE_URL", "").replace("+asyncpg", "")
        if not db_url:
            return _db_words_cache
        engine = create_engine(db_url, pool_size=1, max_overflow=0)
        with engine.connect() as conn:
            rows = conn.execute(text("SELECT word FROM profanity_words")).fetchall()
        _db_words_cache = [r[0] for r in rows]
        _db_cache_ts = now
    except Exception:
        pass  # DB 미연결 시 캐시 그대로 사용
    return _db_words_cache


def _build_patterns(extra_words: Optional[list[str]] = None) -> list[re.Pattern]:
    words = list(_DEFAULT_WORDS) + list(_env_extra) + (extra_words or [])
    return (
        [re.compile(re.escape(w), re.IGNORECASE) for w in words]
        + _CONTEXT_PATTERNS
    )


# 환경변수 기반 패턴 (서버 기동 시 1회 빌드)
_BASE_PATTERNS: list[re.Pattern] = _build_patterns()


def contains_profanity(text: str) -> bool:
    # 기본 패턴으로 먼저 체크 (빠름)
    if any(p.search(text) for p in _BASE_PATTERNS):
        return True
    # DB 금칙어 추가 체크 (캐시됨)
    db_words = _get_db_words()
    if db_words:
        db_patterns = [re.compile(re.escape(w), re.IGNORECASE) for w in db_words]
        return any(p.search(text) for p in db_patterns)
    return False


def mask_profanity(text: str) -> str:
    result = text
    all_patterns = _BASE_PATTERNS + [
        re.compile(re.escape(w), re.IGNORECASE) for w in _get_db_words()
    ]
    for pattern in all_patterns:
        result = pattern.sub(lambda m: "*" * len(m.group()), result)
    return result


def check_profanity(text: str, field: str = "내용") -> None:
    if contains_profanity(text):
        raise ValueError(f"{field}에 사용할 수 없는 단어가 포함되어 있습니다.")
