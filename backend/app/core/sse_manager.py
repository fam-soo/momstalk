"""인메모리 SSE 이벤트 큐 매니저.

단일 인스턴스 배포용. 멀티 인스턴스 환경에서는 Redis Pub/Sub으로 교체 필요.
"""
import asyncio
import json
from collections import defaultdict
from typing import AsyncGenerator

# user_id → set of asyncio.Queue
_queues: dict[int, set[asyncio.Queue]] = defaultdict(set)


def subscribe(user_id: int) -> asyncio.Queue:
    q: asyncio.Queue = asyncio.Queue(maxsize=100)
    _queues[user_id].add(q)
    return q


def unsubscribe(user_id: int, q: asyncio.Queue) -> None:
    _queues[user_id].discard(q)
    if not _queues[user_id]:
        del _queues[user_id]


async def publish(user_id: int, event_type: str, payload: dict) -> None:
    """특정 유저의 모든 SSE 연결에 이벤트 전송."""
    msg = json.dumps({"type": event_type, **payload})
    for q in list(_queues.get(user_id, [])):
        try:
            q.put_nowait(msg)
        except asyncio.QueueFull:
            pass  # 느린 클라이언트는 이벤트 손실 허용


async def event_stream(user_id: int) -> AsyncGenerator[str, None]:
    """SSE 형식 문자열 스트림 제너레이터."""
    q = subscribe(user_id)
    try:
        yield "data: {\"type\": \"connected\"}\n\n"
        while True:
            try:
                msg = await asyncio.wait_for(q.get(), timeout=25)
                yield f"data: {msg}\n\n"
            except asyncio.TimeoutError:
                yield ": heartbeat\n\n"   # keep-alive ping
    finally:
        unsubscribe(user_id, q)
