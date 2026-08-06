"""학원 추천 결과 상위 후보에 대한 AI 비교 설명.

scripts/summarize_reviews.py가 하는 "크롤링 원문 후기 → AI 요약(seed 후기)"과는
역할이 다르다. 여기서는 새 사실을 만들지 않고, DB에 이미 저장된 구조화 필드
(과목/커리큘럼/학원비/정원/숙제량 통계/평점 등)와 사용자의 설문 응답만을 근거로
상위 후보들을 비교 서술한다 — "제공된 데이터 외 추측 금지"를 프롬프트에 강하게
명시해 후기가 없는 학원도 안전하게 비교 대상에 포함할 수 있게 하는 것이 목적.

실패(키 미설정/타임아웃/API 오류)해도 추천 자체는 항상 동작해야 하므로 모든
예외를 흡수하고 None을 반환한다 — 호출부는 기존 규칙 기반 match_reasons로 폴백.
"""
import asyncio
import logging

from app.core.config import settings

logger = logging.getLogger(__name__)

_MAX_CANDIDATES = 5

_SYSTEM_NOTE = (
    "당신은 학부모 커뮤니티 momstalk의 학원 추천 보조입니다. "
    "아래 [학생 정보]와 [후보 학원 데이터]에 명시된 내용만 근거로 학원들을 비교 서술하세요.\n"
    "- 데이터에 없는 내용(강사 실력, 실제 성적 향상 여부, 학원 평판 등)은 절대 언급하거나 추측하지 마세요.\n"
    "- 후기 수(review_count)가 0이거나 적은 학원은 '아직 후기가 적어 참고용'이라고 명시하세요.\n"
    "- 광고 문구, 과장된 표현 없이 담담하고 객관적으로 작성하세요.\n"
    "- 300자 이내, 존댓말, 본문만 출력하세요(제목/설명 없이)."
)


def _build_prompt(child_summary: dict, candidates: list[dict]) -> str:
    lines = [_SYSTEM_NOTE, "", "[학생 정보]", str(child_summary), "", "[후보 학원 데이터]"]
    for c in candidates:
        lines.append(str(c))
    return "\n".join(lines)


def _candidate_payload(item) -> dict:
    """AcademyMatchResult 하나를 프롬프트용 dict로 축약 — DB에 실제로 있는 필드만."""
    a = item.academy
    return {
        "name": a.name,
        "region": a.region,
        "subjects": a.subjects,
        "curriculum_focus": a.curriculum_focus,
        "class_style": a.class_style,
        "avg_class_capacity": a.avg_class_capacity,
        "avg_tuition_10k_won": a.avg_tuition_10k_won,
        "shuttle_bus": a.shuttle_bus,
        "avg_rating": a.avg_rating,
        "review_count": a.user_review_count,
        "has_ai_summary_only": a.has_seed and a.user_review_count == 0,
        "match_score": item.match_score,
    }


def _call_gemini_sync(prompt: str) -> str:
    import google.generativeai as genai

    genai.configure(api_key=settings.GOOGLE_API_KEY)
    model = genai.GenerativeModel(settings.GEMINI_MODEL)
    resp = model.generate_content(prompt)
    return (resp.text or "").strip()


async def generate_comparison(child_summary: dict, results: list) -> str | None:
    """추천 상위 후보(results, 이미 점수순 정렬됨)에 대한 AI 비교 설명을 생성.

    실패 시 None — 호출부에서 그대로 무시하고 기존 match_reasons만 노출한다.
    """
    if not settings.GOOGLE_API_KEY:
        logger.warning("academy AI comparison skipped: GOOGLE_API_KEY not configured")
        return None
    if not results:
        return None

    candidates = [_candidate_payload(r) for r in results[:_MAX_CANDIDATES]]
    prompt = _build_prompt(child_summary, candidates)

    try:
        text = await asyncio.wait_for(asyncio.to_thread(_call_gemini_sync, prompt), timeout=10)
        if not text:
            logger.warning("academy AI comparison returned empty text")
        return text or None
    except Exception as e:
        logger.warning("academy AI comparison failed: %s", e)
        return None
