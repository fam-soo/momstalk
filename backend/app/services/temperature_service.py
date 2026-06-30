"""사용자 온도 (manner_score) 갱신 서비스.

기본 온도: 36.5°C → DB에는 정수 * 10 저장 (365 = 36.5°C)
범위: 0 ~ 1000 (0.0°C ~ 100.0°C)
"""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.service_models import User

# 온도 변화 점수표 (× 10 단위 — DB 저장값, 실제 °C는 /10)
SCORE = {
    "post_created": 1,        # 게시글 작성 +0.1°C
    "comment_created": 1,     # 댓글 작성 +0.1°C
    "post_liked": 2,          # 게시글 좋아요 받음 +0.2°C
    "post_unliked": -2,       # 게시글 좋아요 취소 -0.2°C
    "comment_liked": 1,       # 댓글 좋아요 받음 +0.1°C
    "comment_unliked": -1,    # 댓글 좋아요 취소 -0.1°C
    "post_hidden": -50,       # 신고 누적 블라인드 -5.0°C
    "suspended": -100,        # 계정 정지 -10.0°C
}

_MIN = 0
_MAX = 1000
_DEFAULT = 365  # 36.5°C


async def adjust(user_id: int, event: str, db: AsyncSession) -> None:
    """manner_score를 이벤트에 따라 조정. 범위: 0 ~ 1000."""
    delta = SCORE.get(event, 0)
    if delta == 0:
        return

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        return

    current = user.manner_score if user.manner_score is not None else _DEFAULT
    user.manner_score = max(_MIN, min(_MAX, current + delta))
    # 커밋은 호출자가 담당 (이미 트랜잭션 내에 있음)


def to_celsius(manner_score: int) -> float:
    """manner_score → 온도 (°C)."""
    return round((manner_score if manner_score is not None else _DEFAULT) / 10, 1)


def temperature_color(celsius: float) -> str:
    """온도 범위별 색상 레이블."""
    if celsius >= 60:
        return "red"
    if celsius >= 40:
        return "orange"
    if celsius >= 30:
        return "blue"
    return "grey"
