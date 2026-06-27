from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.sse_manager import event_stream
from app.db import get_service_db
from app.models.service_models import User
from app.schemas.dm import ConversationResponse, MessageCreate, MessageResponse
from app.services import dm_service

router = APIRouter(tags=["dm"])


# ── Block ────────────────────────────────────────────

@router.post("/users/{target_id}/block", status_code=status.HTTP_204_NO_CONTENT)
async def block_user(
    target_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """이 회원의 글 모두 숨기기."""
    try:
        await dm_service.block_user(user, target_id, db)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/users/blocks")
async def list_blocks(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """내가 차단한 유저 목록 조회."""
    return await dm_service.list_blocks(user, db)


@router.delete("/users/{target_id}/block", status_code=status.HTTP_204_NO_CONTENT)
async def unblock_user(
    target_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    await dm_service.unblock_user(user, target_id, db)


# ── Conversation ─────────────────────────────────────

@router.get("/conversations", response_model=list[ConversationResponse])
async def list_conversations(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    return await dm_service.list_conversations(user, db)


@router.post("/conversations/{other_user_id}", response_model=ConversationResponse)
async def start_conversation(
    other_user_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """대화하기 — 기존 대화방이 있으면 반환, 없으면 생성."""
    try:
        conv = await dm_service.get_or_create_conversation(user, other_user_id, db)
        convs = await dm_service.list_conversations(user, db)
        for c in convs:
            if c.id == conv.id:
                return c
        # 방금 생성된 빈 대화방
        from app.models.service_models import User as UserModel
        from sqlalchemy import select
        other = (await db.execute(select(UserModel).where(UserModel.id == other_user_id))).scalar_one_or_none()
        return ConversationResponse(
            id=conv.id,
            other_user_id=other_user_id,
            other_nickname=other.nickname or f"익명{other_user_id}" if other else "알 수 없음",
            unread_count=0,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/conversations/{conv_id}/messages", response_model=list[MessageResponse])
async def list_messages(
    conv_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    try:
        return await dm_service.list_messages(conv_id, user, db)
    except ValueError as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.post("/conversations/{conv_id}/messages", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def send_message(
    conv_id: int,
    req: MessageCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    try:
        return await dm_service.send_message(conv_id, user, req.content, db)
    except ValueError as e:
        raise HTTPException(status_code=403, detail=str(e))


# ── SSE 실시간 스트림 ─────────────────────────────────

@router.get("/stream")
async def dm_stream(user: User = Depends(get_current_user)):
    """Server-Sent Events — DM 실시간 수신.

    클라이언트는 `EventSource('/api/v1/stream', {headers: {Authorization: 'Bearer ...'}})` 로 연결.
    새 메시지 도착 시 `{"type": "new_message", "conversation_id": N, "sender_id": N, ...}` 이벤트 수신.
    """
    return StreamingResponse(
        event_stream(user.id),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",   # nginx 버퍼링 비활성화
        },
    )
