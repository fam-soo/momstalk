"""
관리자 API — MVP.

인증: 일반 유저 JWT + users.is_admin = true
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.db import get_service_db
from app.models.service_models import (
    AdminAction,
    AuthCapture,
    Comment,
    Post,
    Report,
    User,
    UserWarning,
)
from app.services import capture_service
from app.api.deps import get_current_user

router = APIRouter(prefix="/admin", tags=["admin"])


async def _require_admin(user: User = Depends(get_current_user)) -> User:
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="관리자 권한이 필요합니다.")
    return user


# ── 캡처 심사 ─────────────────────────────────────────

@router.get("/captures")
async def list_captures(
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    captures = await capture_service.list_pending_captures(db)
    result = []
    for c in captures:
        user = (await db.execute(select(User).where(User.id == c.user_id))).scalar_one_or_none()
        try:
            image_url = capture_service.generate_get_presign_url(c.s3_key) if c.s3_key else None
        except Exception:
            image_url = None
        result.append({
            "id": c.id,
            "user_id": c.user_id,
            "nickname": user.nickname if user else None,
            "input_school_code": c.input_school_code,
            "input_school_name": c.input_school_name,
            "input_grade": c.input_grade,
            "input_class_num": c.input_class_num,
            "s3_key": c.s3_key,
            "image_url": image_url,
            "created_at": c.created_at.isoformat() if c.created_at else None,
        })
    return result


@router.post("/captures/{capture_id}/approve", status_code=status.HTTP_204_NO_CONTENT)
async def approve_capture(
    capture_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    try:
        await capture_service.approve_capture(capture_id, admin, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


class RejectRequest(BaseModel):
    reason: str


@router.post("/captures/{capture_id}/reject", status_code=status.HTTP_204_NO_CONTENT)
async def reject_capture(
    capture_id: int,
    req: RejectRequest,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    try:
        await capture_service.reject_capture(capture_id, admin, req.reason, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


# ── 유저 관리 ─────────────────────────────────────────

class SuspendRequest(BaseModel):
    days: int
    reason: str


class WarnRequest(BaseModel):
    reason: str


@router.get("/users")
async def list_users(
    q: Optional[str] = Query(None),
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    query = select(User).order_by(User.created_at.desc()).limit(100)
    if q:
        from sqlalchemy import or_, cast, String
        query = select(User).where(
            or_(User.nickname.ilike(f"%{q}%"), cast(User.id, String) == q)
        ).order_by(User.created_at.desc()).limit(50)
    users = (await db.execute(query)).scalars().all()
    return [
        {
            "id": u.id,
            "nickname": u.nickname,
            "school_name": u.school_name,
            "grade": u.grade,
            "member_grade": u.member_grade,
            "is_banned": u.is_banned,
            "suspended_until": u.suspended_until.isoformat() if u.suspended_until else None,
            "warning_count": u.warning_count,
            "created_at": u.created_at.isoformat() if u.created_at else None,
        }
        for u in users
    ]


@router.get("/users/{user_id}")
async def get_user_detail(
    user_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다.")
    warnings = (await db.execute(
        select(UserWarning).where(UserWarning.user_id == user_id).order_by(UserWarning.created_at.desc())
    )).scalars().all()
    post_count = (await db.execute(
        select(func.count()).where(Post.author_id == user_id, Post.is_deleted == False)
    )).scalar()
    return {
        "id": user.id,
        "nickname": user.nickname,
        "school_name": user.school_name,
        "grade": user.grade,
        "member_grade": user.member_grade,
        "is_banned": user.is_banned,
        "suspended_until": user.suspended_until.isoformat() if user.suspended_until else None,
        "warning_count": user.warning_count,
        "post_count": post_count,
        "created_at": user.created_at.isoformat() if user.created_at else None,
        "warnings": [
            {
                "id": w.id,
                "warning_type": w.warning_type,
                "reason": w.reason,
                "expires_at": w.expires_at.isoformat() if w.expires_at else None,
                "created_at": w.created_at.isoformat() if w.created_at else None,
            }
            for w in warnings
        ],
    }


@router.post("/users/{user_id}/approve", status_code=status.HTTP_204_NO_CONTENT)
async def approve_user(
    user_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    """lurker → member 직접 승격 (캡처 없이 관리자가 수동 승인)."""
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다.")
    user.member_grade = "member"
    user.auth_pending = False
    db.add(AdminAction(admin_id=admin.id, action_type="approve_user", target_type="user", target_id=user_id, detail="관리자 수동 승인"))
    await db.commit()


@router.post("/users/{user_id}/warn", status_code=status.HTTP_204_NO_CONTENT)
async def warn_user(
    user_id: int,
    req: WarnRequest,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다.")
    user.warning_count = (user.warning_count or 0) + 1
    db.add(UserWarning(user_id=user_id, reason=req.reason, warning_type="warning", issued_by=admin.id))
    db.add(AdminAction(admin_id=admin.id, action_type="warn", target_type="user", target_id=user_id, detail=req.reason))
    await db.commit()


@router.post("/users/{user_id}/suspend", status_code=status.HTTP_204_NO_CONTENT)
async def suspend_user(
    user_id: int,
    req: SuspendRequest,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다.")
    user.suspended_until = datetime.utcnow() + timedelta(days=req.days)
    user.warning_count = (user.warning_count or 0) + 1
    db.add(AdminAction(admin_id=admin.id, action_type=f"suspend_{req.days}d", target_type="user", target_id=user_id, detail=req.reason))
    db.add(UserWarning(user_id=user_id, reason=req.reason, warning_type=f"suspend_{req.days}d", issued_by=admin.id, expires_at=user.suspended_until))
    await db.commit()


@router.post("/users/{user_id}/ban", status_code=status.HTTP_204_NO_CONTENT)
async def ban_user(
    user_id: int,
    req: WarnRequest,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다.")
    user.is_banned = True
    db.add(AdminAction(admin_id=admin.id, action_type="ban", target_type="user", target_id=user_id, detail=req.reason))
    db.add(UserWarning(user_id=user_id, reason=req.reason, warning_type="banned", issued_by=admin.id))
    await db.commit()


@router.post("/users/{user_id}/unban", status_code=status.HTTP_204_NO_CONTENT)
async def unban_user(
    user_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다.")
    user.is_banned = False
    user.suspended_until = None
    db.add(AdminAction(admin_id=admin.id, action_type="unban", target_type="user", target_id=user_id))
    await db.commit()


# ── 게시글 관리 ───────────────────────────────────────

@router.post("/posts/{post_id}/hide", status_code=status.HTTP_204_NO_CONTENT)
async def hide_post(
    post_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    post = (await db.execute(select(Post).where(Post.id == post_id))).scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다.")
    post.is_hidden = True
    db.add(AdminAction(admin_id=admin.id, action_type="hide_post", target_type="post", target_id=post_id))
    await db.commit()


@router.post("/posts/{post_id}/unhide", status_code=status.HTTP_204_NO_CONTENT)
async def unhide_post(
    post_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    post = (await db.execute(select(Post).where(Post.id == post_id))).scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다.")
    post.is_hidden = False
    db.add(AdminAction(admin_id=admin.id, action_type="unhide_post", target_type="post", target_id=post_id))
    await db.commit()


@router.delete("/posts/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def force_delete_post(
    post_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    post = (await db.execute(select(Post).where(Post.id == post_id))).scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다.")
    post.is_deleted = True
    post.is_hidden = True
    db.add(AdminAction(admin_id=admin.id, action_type="delete_post", target_type="post", target_id=post_id))
    await db.commit()


# ── 신고 목록 ─────────────────────────────────────────

@router.get("/reports")
async def list_reports(
    status_filter: str = "pending",
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    result = await db.execute(
        select(Report).where(Report.status == status_filter).order_by(Report.created_at.desc()).limit(100)
    )
    reports = result.scalars().all()

    items = []
    for r in reports:
        content_preview = None
        if r.target_type == "post":
            post = (await db.execute(select(Post).where(Post.id == r.target_id))).scalar_one_or_none()
            if post:
                content_preview = f"[제목] {post.title}\n[내용] {post.content[:200]}"
        elif r.target_type == "comment":
            comment = (await db.execute(select(Comment).where(Comment.id == r.target_id))).scalar_one_or_none()
            if comment:
                content_preview = comment.content[:200]
        items.append({
            "id": r.id,
            "reporter_id": r.reporter_id,
            "target_type": r.target_type,
            "target_id": r.target_id,
            "category": r.category,
            "reason": r.reason,
            "status": r.status,
            "content_preview": content_preview,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        })
    return items


class ReviewReportRequest(BaseModel):
    action: str  # warn / suspend_7d / suspend_30d / ban / cleared
    reason: str = ""


@router.post("/reports/{report_id}/review", status_code=status.HTTP_204_NO_CONTENT)
async def review_report(
    report_id: int,
    req: ReviewReportRequest,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    report = (await db.execute(select(Report).where(Report.id == report_id))).scalar_one_or_none()
    if not report:
        raise HTTPException(status_code=404, detail="신고를 찾을 수 없습니다.")

    report.status = "dismissed" if req.action == "cleared" else "actioned"
    report.reviewed_by = admin.id
    report.reviewed_at = datetime.utcnow()
    report.action_taken = req.action
    db.add(AdminAction(admin_id=admin.id, action_type=f"report_{req.action}", target_type=report.target_type, target_id=report.target_id, detail=req.reason))

    # 작성자 조회
    author_id: Optional[int] = None
    if report.target_type == "post":
        post = (await db.execute(select(Post).where(Post.id == report.target_id))).scalar_one_or_none()
        if post:
            author_id = post.author_id
            if req.action != "cleared":
                post.is_hidden = True
    elif report.target_type == "comment":
        comment = (await db.execute(select(Comment).where(Comment.id == report.target_id))).scalar_one_or_none()
        if comment:
            author_id = comment.author_id
            if req.action != "cleared":
                comment.is_hidden = True

    # 작성자 제재 적용
    if author_id and req.action != "cleared":
        user = (await db.execute(select(User).where(User.id == author_id))).scalar_one_or_none()
        if user:
            if req.action == "warn":
                user.warning_count = (user.warning_count or 0) + 1
                db.add(UserWarning(user_id=author_id, reason=req.reason or "신고 누적", warning_type="warning", issued_by=admin.id))
            elif req.action == "suspend_7d":
                user.suspended_until = datetime.utcnow() + timedelta(days=7)
                user.warning_count = (user.warning_count or 0) + 1
                db.add(UserWarning(user_id=author_id, reason=req.reason or "신고 처리", warning_type="suspend_7d", issued_by=admin.id, expires_at=user.suspended_until))
            elif req.action == "suspend_30d":
                user.suspended_until = datetime.utcnow() + timedelta(days=30)
                user.warning_count = (user.warning_count or 0) + 1
                db.add(UserWarning(user_id=author_id, reason=req.reason or "신고 처리", warning_type="suspend_30d", issued_by=admin.id, expires_at=user.suspended_until))
            elif req.action == "ban":
                user.is_banned = True
                db.add(UserWarning(user_id=author_id, reason=req.reason or "영구 정지", warning_type="banned", issued_by=admin.id))

    await db.commit()
