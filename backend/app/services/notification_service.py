from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.fcm import send_push_to_user
from app.models.service_models import Notification


async def notify_user(
    db: AsyncSession,
    user_id: int,
    ntype: str,
    title: str,
    body: str,
    data: dict | None = None,
) -> None:
    """알림함에 기록을 남기고 동시에 FCM 푸시를 보낸다.

    기존에는 send_push_to_user만 호출해 기기가 꺼져있거나 알림 권한이 없으면
    알림이 그대로 유실됐다. 알림함(GET /notifications)에서 다시 볼 수 있도록
    항상 먼저 DB에 기록한 뒤 푸시를 시도한다.
    """
    db.add(Notification(user_id=user_id, type=ntype, title=title, body=body, data=data))
    await db.commit()
    await send_push_to_user(db, user_id, title=title, body=body, data=data)


async def list_notifications(db: AsyncSession, user_id: int, limit: int = 50) -> list[Notification]:
    result = await db.execute(
        select(Notification)
        .where(Notification.user_id == user_id)
        .order_by(Notification.created_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def unread_count(db: AsyncSession, user_id: int) -> int:
    result = await db.execute(
        select(func.count()).where(Notification.user_id == user_id, Notification.is_read == False)
    )
    return result.scalar() or 0


async def mark_read(db: AsyncSession, user_id: int, notification_id: int) -> None:
    notif = (await db.execute(
        select(Notification).where(Notification.id == notification_id, Notification.user_id == user_id)
    )).scalar_one_or_none()
    if notif and not notif.is_read:
        notif.is_read = True
        await db.commit()


async def mark_all_read(db: AsyncSession, user_id: int) -> None:
    await db.execute(
        Notification.__table__.update()
        .where(Notification.user_id == user_id, Notification.is_read == False)
        .values(is_read=True)
    )
    await db.commit()
