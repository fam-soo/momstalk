"""Redis 슬라이딩 윈도우 Rate Limiter.

사용법:
    from app.core.rate_limit import RateLimit
    @router.post("/sms/send")
    async def send_sms(req: Request, ...):
        await RateLimit.sms(req)
        ...
"""
import time
from typing import Optional

from fastapi import HTTPException, Request, status

_redis = None


async def _get_redis():
    global _redis
    if _redis is None:
        try:
            import redis.asyncio as aioredis
            from app.core.config import settings
            _redis = aioredis.from_url(settings.REDIS_URL, encoding="utf-8", decode_responses=True)
            await _redis.ping()
        except Exception:
            _redis = None
    return _redis


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


async def _check(key: str, limit: int, window_sec: int, request: Optional[Request] = None) -> None:
    """슬라이딩 윈도우: Redis ZSET 기반. Redis 미사용 시 통과."""
    r = await _get_redis()
    if r is None:
        return

    now = time.time()
    window_start = now - window_sec

    pipe = r.pipeline()
    pipe.zremrangebyscore(key, "-inf", window_start)
    pipe.zadd(key, {str(now): now})
    pipe.zcard(key)
    pipe.expire(key, window_sec + 1)
    results = await pipe.execute()

    count = results[2]
    if count > limit:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"요청이 너무 많습니다. {window_sec}초 후 다시 시도해주세요.",
            headers={"Retry-After": str(window_sec)},
        )


class RateLimit:
    """엔드포인트별 Rate Limit 규칙."""

    @staticmethod
    async def sms(request: Request) -> None:
        """SMS 발송: IP당 5분에 3회"""
        ip = _client_ip(request)
        await _check(f"rl:sms:{ip}", limit=3, window_sec=300, request=request)

    @staticmethod
    async def post_create(request: Request) -> None:
        """게시글 작성: IP당 1분에 5회"""
        ip = _client_ip(request)
        await _check(f"rl:post:{ip}", limit=5, window_sec=60, request=request)

    @staticmethod
    async def comment_create(request: Request) -> None:
        """댓글 작성: IP당 1분에 10회"""
        ip = _client_ip(request)
        await _check(f"rl:comment:{ip}", limit=10, window_sec=60, request=request)

    @staticmethod
    async def login(request: Request) -> None:
        """로그인 시도: IP당 5분에 10회"""
        ip = _client_ip(request)
        await _check(f"rl:login:{ip}", limit=10, window_sec=300, request=request)

    @staticmethod
    async def report(request: Request) -> None:
        """신고: IP당 1분에 5회"""
        ip = _client_ip(request)
        await _check(f"rl:report:{ip}", limit=5, window_sec=60, request=request)

    @staticmethod
    async def academy_search(request: Request) -> None:
        """학원 검색: IP당 1분에 30회 (스크래핑 방어)"""
        ip = _client_ip(request)
        await _check(f"rl:acad_search:{ip}", limit=30, window_sec=60, request=request)

    @staticmethod
    async def academy_detail(request: Request) -> None:
        """학원 상세/후기: IP당 1분에 60회"""
        ip = _client_ip(request)
        await _check(f"rl:acad_detail:{ip}", limit=60, window_sec=60, request=request)

    @staticmethod
    async def school_search(request: Request) -> None:
        """학교 검색: IP당 1분에 20회"""
        ip = _client_ip(request)
        await _check(f"rl:school:{ip}", limit=20, window_sec=60, request=request)
