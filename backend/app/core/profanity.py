"""서버 사이드 금칙어 필터.

금칙어는 환경변수 PROFANITY_WORDS(콤마 구분)로 추가 가능.
"""
import os
import re

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
_ALL_WORDS: list[str] = _DEFAULT_WORDS + _env_extra

_PATTERNS: list[re.Pattern] = (
    [re.compile(re.escape(w), re.IGNORECASE) for w in _ALL_WORDS]
    + _CONTEXT_PATTERNS
)


def contains_profanity(text: str) -> bool:
    return any(p.search(text) for p in _PATTERNS)


def mask_profanity(text: str) -> str:
    result = text
    for pattern in _PATTERNS:
        result = pattern.sub(lambda m: "*" * len(m.group()), result)
    return result


def check_profanity(text: str, field: str = "내용") -> None:
    if contains_profanity(text):
        raise ValueError(f"{field}에 사용할 수 없는 단어가 포함되어 있습니다.")
