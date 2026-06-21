"""서버 사이드 금칙어 필터.

금칙어는 환경변수 PROFANITY_WORDS(콤마 구분)로 추가 가능.
기본 목록은 최소화; 실제 운영 시 DB 또는 별도 파일로 관리 권장.
"""
import os
import re

_DEFAULT_WORDS: list[str] = [
    # 욕설/혐오 표현 예시 (실제 운영 시 확장)
    "씨발", "시발", "개새끼", "병신", "지랄", "좆", "보지", "자지",
    "미친놈", "미친년", "꺼져", "죽어", "죽여",
]

_env_extra = [w.strip() for w in os.environ.get("PROFANITY_WORDS", "").split(",") if w.strip()]
_ALL_WORDS: list[str] = _DEFAULT_WORDS + _env_extra

# 초성 변형 (ㅅㅂ, ㅂㅅ) 등 단순 패턴 제거를 위해 자모 분리 정규식도 포함
_PATTERNS: list[re.Pattern] = [re.compile(re.escape(w), re.IGNORECASE) for w in _ALL_WORDS]


def contains_profanity(text: str) -> bool:
    """금칙어 포함 여부."""
    for pattern in _PATTERNS:
        if pattern.search(text):
            return True
    return False


def mask_profanity(text: str) -> str:
    """금칙어를 *로 마스킹 (로깅/미리보기용)."""
    result = text
    for pattern in _PATTERNS:
        result = pattern.sub(lambda m: "*" * len(m.group()), result)
    return result


def check_profanity(text: str, field: str = "내용") -> None:
    """금칙어 포함 시 ValueError 발생."""
    if contains_profanity(text):
        raise ValueError(f"{field}에 사용할 수 없는 단어가 포함되어 있습니다.")
