"""학원의 대상 학교급(초/중/고) 추론.

NEIS 학원 데이터에는 "대상 학교급" 필드가 없어(academies.school_type은
계열명일 뿐 학교급이 아님 — Academy.target_school_types 컬럼 주석 참고),
학원명과 후기 텍스트에 등장하는 학년 언급으로 추론한다. 여러 학교급을
동시에 다루는 학원(예: 초중등 종합)도 있으므로 리스트로 저장한다.

근거를 찾지 못하면 빈 리스트를 반환한다 — 이 경우 호출부(academy_service)는
필터에서 "불명"으로 취급해 제외하지 않고 통과시킨다(잘못 추론해서 후보를
과도하게 걸러내는 것보다, 모르면 통과시키는 쪽이 안전).
"""
import re

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
