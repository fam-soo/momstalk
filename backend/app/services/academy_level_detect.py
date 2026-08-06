"""학원의 대상 학교급(초/중/고) 추론.

NEIS 학원 데이터에는 "대상 학교급" 필드가 없어(academies.school_type은
계열명일 뿐 학교급이 아님 — Academy.target_school_types 컬럼 주석 참고),
학원명과 후기 텍스트에 등장하는 학년 언급으로 추론한다. 여러 학교급을
동시에 다루는 학원(예: 초중등 종합)도 있으므로 리스트로 저장한다.

근거를 찾지 못하면 빈 리스트를 반환한다 — 이 경우 호출부(academy_service)는
필터에서 "불명"으로 취급해 제외하지 않고 통과시킨다(잘못 추론해서 후보를
과도하게 걸러내는 것보다, 모르면 통과시키는 쪽이 안전).
"""
import asyncio
import json
import logging
import re

from app.core.config import settings

logger = logging.getLogger(__name__)

_ELEMENTARY_PATTERNS = [
    re.compile(r"초등"),
    re.compile(r"초\s*[1-6]\b"),
    re.compile(r"예비\s*초"),
]
_MIDDLE_PATTERNS = [
    re.compile(r"중등"),
    re.compile(r"중\s*[1-3]\b"),
    re.compile(r"예비\s*중"),
]
_HIGH_PATTERNS = [
    re.compile(r"고등"),
    re.compile(r"고\s*[1-3]\b"),
    re.compile(r"예비\s*고"),
    re.compile(r"고3|재수|N수|수능"),
]

_LEVEL_PATTERNS = [
    ("elementary", _ELEMENTARY_PATTERNS),
    ("middle", _MIDDLE_PATTERNS),
    ("high", _HIGH_PATTERNS),
]


def detect_from_text(*texts: str | None) -> list[str]:
    """학원명/후기 학년 언급 등 텍스트 여러 개를 모아 대상 학교급을 추론한다."""
    joined = " ".join(t for t in texts if t)
    if not joined:
        return []
    found = []
    for level, patterns in _LEVEL_PATTERNS:
        if any(p.search(joined) for p in patterns):
            found.append(level)
    return found


def detect_school_types(name: str, review_grade_texts: list[str] | None = None) -> list[str]:
    """학원명 + (있으면) 오늘학교 리뷰의 student_grade 언급을 종합해 추론.

    review_grade_texts: scrape_onaul.py가 리뷰 헤더에서 뽑아낸 "student_grade"
    문자열 목록(예: ["초3", "중1", "고2"]) — 있으면 이름만 볼 때보다 신뢰도가 높다.
    """
    return detect_from_text(name, *(review_grade_texts or []))


# ── AI 보강 분류 (정규식으로 못 잡은 이름만 대상) ──────────────────────────
#
# 여기서 Gemini에게 요구하는 건 "학원에 대해 알고 있는 걸 말해달라"가 아니라
# "주어진 학원명 텍스트만 보고 초/중/고 중 어디에 해당할지 분류해달라"는
# 순수 분류 작업이다. 학원명 외의 사실을 만들어내지 않도록, 확신이 없으면
# 반드시 빈 배열(불명)로 답하게 강하게 제약한다 — 불명으로 남으면 기존
# 필터 로직상 제외되지 않고 그냥 통과되므로 잘못 채우는 것보다 안전하다.
CLASSIFY_BATCH_SIZE = 50

_CLASSIFY_SYSTEM_NOTE = (
    "아래는 학원 이름 목록입니다. 각 이름만 보고(외부 지식 추측 금지) "
    "그 학원이 초등학생(elementary)/중학생(middle)/고등학생(high) 중 "
    "누구를 대상으로 하는지 분류하세요. 여러 학교급을 동시에 다룰 수도 있습니다.\n"
    "- 이름에 학교급을 짐작할 단서가 전혀 없으면 반드시 빈 배열 []로 답하세요. 절대 추측하지 마세요.\n"
    "- 결과는 입력과 같은 순서, 같은 개수의 JSON 배열의 배열로만 출력하세요.\n"
    '  예: [["elementary"], [], ["middle","high"]]\n'
    "- 다른 설명 없이 JSON만 출력하세요."
)


def _build_classify_prompt(names: list[str]) -> str:
    numbered = "\n".join(f"{i+1}. {n}" for i, n in enumerate(names))
    return f"{_CLASSIFY_SYSTEM_NOTE}\n\n[학원 이름 목록]\n{numbered}"


def _call_gemini_classify_sync(prompt: str) -> str:
    import google.generativeai as genai

    genai.configure(api_key=settings.GOOGLE_API_KEY)
    model = genai.GenerativeModel(settings.GEMINI_MODEL)
    resp = model.generate_content(prompt)
    return (resp.text or "").strip()


def _parse_classify_response(text: str, expected_len: int) -> list[list[str]] | None:
    cleaned = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.MULTILINE).strip()
    try:
        data = json.loads(cleaned)
    except Exception:
        return None
    if not isinstance(data, list) or len(data) != expected_len:
        return None
    valid = {"elementary", "middle", "high"}
    result = []
    for item in data:
        if not isinstance(item, list):
            return None
        result.append([lv for lv in item if lv in valid])
    return result


async def classify_batch(names: list[str]) -> list[list[str]]:
    """이름 목록을 Gemini로 분류. 실패 시 전부 빈 배열(불명)로 폴백 — 절대 예외를 던지지 않는다."""
    if not settings.GOOGLE_API_KEY or not names:
        return [[] for _ in names]

    prompt = _build_classify_prompt(names)
    try:
        text = await asyncio.wait_for(asyncio.to_thread(_call_gemini_classify_sync, prompt), timeout=30)
        parsed = _parse_classify_response(text, len(names))
        if parsed is None:
            logger.warning("academy school-type AI classify: unparseable response, falling back to unknown")
            return [[] for _ in names]
        return parsed
    except Exception as e:
        logger.warning("academy school-type AI classify failed: %s", e)
        return [[] for _ in names]
