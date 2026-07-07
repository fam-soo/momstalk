from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError

from app.core.fcm import send_push_to_user
from app.core.sse_manager import publish as sse_publish
from app.models.service_models import Block, Conversation, DirectMessage, User
from app.schemas.dm import ConversationResponse, MessageResponse


# ── Block ────────────────────────────────────────────


async def block_user(user: User, target_id: int, db: AsyncSession) -> None:
    if user.id == target_id:
        raise ValueError("자신을 차단할 수 없습니다.")
    try:
        db.add(Block(user_id=user.id, blocked_user_id=target_id))
        await db.commit()
    except IntegrityError:
        await db.rollback()  # 이미 차단됨 — 무시


async def unblock_user(user: User, target_id: int, db: AsyncSession) -> None:
    result = await db.execute(
        select(Block).where(Block.user_id == user.id, Block.blocked_user_id == target_id)
    )
    block = result.scalar_one_or_none()
    if block:
        await db.delete(block)
        await db.commit()


async def get_blocked_ids(user_id: int, db: AsyncSession) -> set[int]:
    result = await db.execute(select(Block.blocked_user_id).where(Block.user_id == user_id))
    return {row for row in result.scalars()}


async def list_blocks(user: User, db: AsyncSession) -> list[dict]:
    """내가 차단한 유저 목록 반환."""
    result = await db.execute(
        select(Block, User)
        .join(User, User.id == Block.blocked_user_id)
        .where(Block.user_id == user.id)
        .order_by(Block.created_at.desc())
    )
    rows = result.all()
    return [
        {"user_id": blocked_user.id, "nickname": blocked_user.nickname or f"익명{blocked_user.id}"}
        for block, blocked_user in rows
    ]


# ── Conversation ─────────────────────────────────────


def _conv_key(a: int, b: int) -> tuple[int, int]:
    return (min(a, b), max(a, b))


async def get_or_create_conversation(user: User, other_id: int, db: AsyncSession) -> Conversation:
    if user.id == other_id:
        raise ValueError("자신과 대화할 수 없습니다.")
    a, b = _conv_key(user.id, other_id)
    result = await db.execute(
        select(Conversation).where(Conversation.user_a_id == a, Conversation.user_b_id == b)
    )
    conv = result.scalar_one_or_none()
    if not conv:
        conv = Conversation(user_a_id=a, user_b_id=b)
        db.add(conv)
        await db.commit()
        await db.refresh(conv)
    return conv


async def list_conversations(user: User, db: AsyncSession) -> list[ConversationResponse]:
    result = await db.execute(
        select(Conversation).where(
            (Conversation.user_a_id == user.id) | (Conversation.user_b_id == user.id)
        ).order_by(Conversation.last_message_at.desc().nullslast())
    )
    convs = result.scalars().all()

    items = []
    for conv in convs:
        other_id = conv.user_b_id if conv.user_a_id == user.id else conv.user_a_id
        other = (await db.execute(select(User).where(User.id == other_id))).scalar_one_or_none()
        last_msg = (await db.execute(
            select(DirectMessage)
            .where(DirectMessage.conversation_id == conv.id)
            .order_by(DirectMessage.created_at.desc())
            .limit(1)
        )).scalar_one_or_none()
        unread = (await db.execute(
            select(func.count()).where(
                DirectMessage.conversation_id == conv.id,
                DirectMessage.sender_id != user.id,
                DirectMessage.is_read == False,
            )
        )).scalar() or 0

        items.append(ConversationResponse(
            id=conv.id,
            other_user_id=other_id,
            other_nickname=other.nickname or f"익명{other_id}" if other else "알 수 없음",
            last_message=last_msg.content if last_msg else None,
            last_message_at=last_msg.created_at if last_msg else None,
            unread_count=unread,
        ))
    return items


async def list_messages(conv_id: int, user: User, db: AsyncSession) -> list[MessageResponse]:
    conv = (await db.execute(select(Conversation).where(Conversation.id == conv_id))).scalar_one_or_none()
    if not conv or user.id not in (conv.user_a_id, conv.user_b_id):
        raise ValueError("대화방에 접근할 수 없습니다.")

    # 읽음 처리
    result = await db.execute(
        select(DirectMessage).where(
            DirectMessage.conversation_id == conv_id,
            DirectMessage.sender_id != user.id,
            DirectMessage.is_read == False,
        )
    )
    for msg in result.scalars().all():
        msg.is_read = True
    await db.commit()

    msgs = (await db.execute(
        select(DirectMessage).where(DirectMessage.conversation_id == conv_id).order_by(DirectMessage.created_at)
    )).scalars().all()

    return [MessageResponse(
        id=m.id, conversation_id=m.conversation_id, sender_id=m.sender_id,
        content=m.content, is_read=m.is_read, created_at=m.created_at,
    ) for m in msgs]


async def send_message(conv_id: int, user: User, content: str, db: AsyncSession) -> MessageResponse:
    conv = (await db.execute(select(Conversation).where(Conversation.id == conv_id))).scalar_one_or_none()
    if not conv or user.id not in (conv.user_a_id, conv.user_b_id):
        raise ValueError("대화방에 접근할 수 없습니다.")

    recipient_id = conv.user_b_id if conv.user_a_id == user.id else conv.user_a_id

    # 양방향 차단 검증 (A→B 또는 B→A 차단 시 메시지 불가)
    from sqlalchemy import or_ as sql_or
    block_check = (await db.execute(
        select(Block).where(sql_or(
            (Block.user_id == user.id) & (Block.blocked_user_id == recipient_id),
            (Block.user_id == recipient_id) & (Block.blocked_user_id == user.id),
        ))
    )).scalar_one_or_none()
    if block_check:
        raise ValueError("차단 관계로 인해 메시지를 보낼 수 없습니다.")

    from datetime import datetime
    msg = DirectMessage(conversation_id=conv_id, sender_id=user.id, content=content)
    db.add(msg)
    conv.last_message_at = datetime.utcnow()
    await db.commit()
    await db.refresh(msg)

    response = MessageResponse(
        id=msg.id, conversation_id=msg.conversation_id, sender_id=msg.sender_id,
        content=msg.content, is_read=msg.is_read, created_at=msg.created_at,
    )

    # 수신자에게 SSE 이벤트 전송
    await sse_publish(recipient_id, "new_message", {
        "conversation_id": conv_id,
        "sender_id": user.id,
        "content": content,
        "created_at": msg.created_at.isoformat(),
    })

    # 수신자 FCM 푸시 (SSE 미연결 상태 또는 백그라운드 앱)
    sender_name = user.nickname or "익명"
    await send_push_to_user(
        db, recipient_id,
        title=f"{sender_name}님의 메시지",
        body=content[:80],
        data={"type": "dm", "conversation_id": str(conv_id)},
    )

    return response
