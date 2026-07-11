from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.fcm import send_push_to_user
from app.models.service_models import Notification, NotificationPreference, User, UserChild


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


# ── 게시판 종류별 "새 글 알림" 설정 ──────────────────────────────

async def get_prefs(db: AsyncSession, user_id: int) -> NotificationPreference:
    pref = (await db.execute(
        select(NotificationPreference).where(NotificationPreference.user_id == user_id)
    )).scalar_one_or_none()
    if pref is None:
        # 최초 조회 시 기본값(전부 False) 행을 만들어 이후 업데이트를 단순하게 유지
        pref = NotificationPreference(user_id=user_id)
        db.add(pref)
        await db.commit()
        await db.refresh(pref)
    return pref


async def update_prefs(db: AsyncSession, user_id: int, **fields: bool) -> NotificationPreference:
    pref = await get_prefs(db, user_id)
    for key, value in fields.items():
        if value is not None:
            setattr(pref, key, value)
    await db.commit()
    await db.refresh(pref)
    return pref


async def notify_new_post(db: AsyncSession, post) -> None:
    """지역/학교/학년 게시판에 새 글이 올라오면, 해당 종류의 알림을 켜둔
    같은 범위 유저들에게 발송한다(작성자 본인 제외). 공지(notice)·전체(free)
    게시판은 대상에서 제외 — notice는 이미 상단 고정으로 눈에 띄고, free는
    "범위"라는 개념이 없어 이 기능의 대상으로 적합하지 않음."""
    if post.board_type not in ("region", "school", "grade"):
        return

    author = (await db.execute(select(User).where(User.id == post.author_id))).scalar_one_or_none()
    if not author:
        return

    if post.board_type == "region":
        region = author.region
        if not region:
            return
        recipients = (await db.execute(
            select(User.id).where(
                User.region == region, User.id != post.author_id, User.is_admin.is_(False),
            )
            .join(NotificationPreference, NotificationPreference.user_id == User.id)
            .where(NotificationPreference.notify_region.is_(True))
        )).scalars().all()
        label = f"{region} 지역"
    else:
        if not post.school_code:
            return
        query = (
            select(UserChild.user_id)
            .join(User, User.id == UserChild.user_id)
            .join(NotificationPreference, NotificationPreference.user_id == User.id)
            .where(UserChild.school_code == post.school_code, User.id != post.author_id, User.is_admin.is_(False))
            .distinct()
        )
        if post.board_type == "grade":
            if not post.grade:
                return
            query = query.where(UserChild.grade == post.grade, NotificationPreference.notify_grade.is_(True))
            label = f"{post.grade}학년"
        else:
            query = query.where(NotificationPreference.notify_school.is_(True))
            label = "학교"
        recipients = (await db.execute(query)).scalars().all()

    for user_id in recipients:
        await notify_user(
            db, user_id, "new_post",
            title=f"{label} 게시판에 새 글이 올라왔어요",
            body=post.title,
            data={"type": "comment", "post_id": str(post.id)},  # 클릭 시 게시글로 이동 (comment와 동일한 라우팅)
        )


async def notify_new_academy_review(db: AsyncSession, review, academy) -> None:
    """즐겨찾기(알림 on) 설정한 유저에게 같은 지역 학원의 새 후기를 알린다."""
    if not academy.region:
        return
    recipients = (await db.execute(
        select(User.id)
        .join(NotificationPreference, NotificationPreference.user_id == User.id)
        .where(
            User.region == academy.region,
            User.id != review.author_id,
            User.is_admin.is_(False),
            NotificationPreference.notify_academy.is_(True),
        )
    )).scalars().all()
    for user_id in recipients:
        await notify_user(
            db, user_id, "new_academy_review",
            title=f"{academy.name}에 새 후기가 올라왔어요",
            body=review.review_text[:60],
            data={"type": "academy", "academy_id": str(academy.id)},
        )
