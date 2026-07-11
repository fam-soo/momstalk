from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from app.api.deps import get_current_user
from app.db import get_db
from app.models.service_models import User
from app.services import notification_service

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("")
async def list_notifications(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    items = await notification_service.list_notifications(db, user.id)
    return {
        "items": [
            {
                "id": n.id,
                "type": n.type,
                "title": n.title,
                "body": n.body,
                "data": n.data,
                "is_read": n.is_read,
                "created_at": n.created_at.isoformat() if n.created_at else None,
            }
            for n in items
        ],
    }


@router.get("/unread-count")
async def get_unread_count(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return {"count": await notification_service.unread_count(db, user.id)}


@router.post("/{notification_id}/read", status_code=204)
async def mark_read(
    notification_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await notification_service.mark_read(db, user.id, notification_id)


@router.post("/read-all", status_code=204)
async def mark_all_read(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await notification_service.mark_all_read(db, user.id)


def _prefs_dict(pref) -> dict:
    return {
        "notify_region": pref.notify_region,
        "notify_school": pref.notify_school,
        "notify_grade": pref.notify_grade,
        "notify_academy": pref.notify_academy,
    }


@router.get("/prefs")
async def get_notification_prefs(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """지역/학교/학년/학원 게시판 "새 글 알림" 종류별 on/off 현황."""
    return _prefs_dict(await notification_service.get_prefs(db, user.id))


class NotificationPrefsUpdate(BaseModel):
    notify_region: Optional[bool] = None
    notify_school: Optional[bool] = None
    notify_grade: Optional[bool] = None
    notify_academy: Optional[bool] = None


@router.patch("/prefs")
async def update_notification_prefs(
    req: NotificationPrefsUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    pref = await notification_service.update_prefs(db, user.id, **req.model_dump())
    return _prefs_dict(pref)
