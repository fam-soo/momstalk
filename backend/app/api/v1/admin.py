"""
관리자 API — MVP.

인증: POST /admin/login → admin_token (별도 JWT, sub prefix "admin:")
이후 Authorization: Bearer admin_token 으로 모든 /admin/* 호출.
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.core.config import settings
from app.db import get_service_db
from app.models.service_models import (
    AdminAction,
    AdminUser,
    AuthCapture,
    Comment,
    Post,
    Report,
    User,
    UserWarning,
)
from app.services import capture_service

from passlib.context import CryptContext
from jose import jwt as jose_jwt, JWTError
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

_pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")

router = APIRouter(prefix="/admin", tags=["admin"])
_bearer = HTTPBearer()


# ── 관리자 JWT 헬퍼 ──────────────────────────────────

def _create_admin_token(admin_id: int) -> str:
    payload = {
        "sub": f"admin:{admin_id}",
        "type": "admin_access",
        "exp": datetime.utcnow() + timedelta(hours=8),
    }
    return jose_jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


async def _get_admin(
    cred: HTTPAuthorizationCredentials = Depends(_bearer),
    db: AsyncSession = Depends(get_service_db),
) -> AdminUser:
    try:
        payload = jose_jwt.decode(cred.credentials, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("type") != "admin_access":
            raise JWTError()
        sub: str = payload["sub"]
        if not sub.startswith("admin:"):
            raise JWTError()
        admin_id = int(sub.split(":")[1])
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="관리자 인증이 필요합니다.")

    admin = (await db.execute(select(AdminUser).where(AdminUser.id == admin_id, AdminUser.is_active == True))).scalar_one_or_none()
    if not admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="비활성 관리자 계정입니다.")
    return admin


# ── 로그인 ────────────────────────────────────────────

class AdminLoginRequest(BaseModel):
    username: str
    password: str


@router.post("/login")
async def admin_login(req: AdminLoginRequest, db: AsyncSession = Depends(get_service_db)):
    admin = (await db.execute(
        select(AdminUser).where(AdminUser.username == req.username, AdminUser.is_active == True)
    )).scalar_one_or_none()
    if not admin or not _pwd_ctx.verify(req.password, admin.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="잘못된 자격증명입니다.")
    return {"admin_token": _create_admin_token(admin.id), "role": admin.role}


# ── 관리자 계정 생성 (superadmin 전용, 최초 1회 seed용) ──

class CreateAdminRequest(BaseModel):
    username: str
    password: str
    role: str = "moderator"


@router.post("/users", status_code=status.HTTP_201_CREATED)
async def create_admin(
    req: CreateAdminRequest,
    admin: AdminUser = Depends(_get_admin),
    db: AsyncSession = Depends(get_service_db),
):
    if admin.role != "superadmin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="superadmin 권한이 필요합니다.")
    hashed = _pwd_ctx.hash(req.password)
    new_admin = AdminUser(username=req.username, hashed_password=hashed, role=req.role)
    db.add(new_admin)
    await db.commit()
    return {"id": new_admin.id, "username": new_admin.username, "role": new_admin.role}


# ── 캡처 심사 ─────────────────────────────────────────

@router.get("/captures")
async def list_captures(
    admin: AdminUser = Depends(_get_admin),
    db: AsyncSession = Depends(get_service_db),
):
    captures = await capture_service.list_pending_captures(db)
    result = []
    for c in captures:
        user = (await db.execute(select(User).where(User.id == c.user_id))).scalar_one_or_none()
        result.append({
            "id": c.id,
            "user_id": c.user_id,
            "nickname": user.nickname if user else None,
            "input_school_code": c.input_school_code,
            "input_school_name": c.input_school_name,
            "input_grade": c.input_grade,
            "input_class_num": c.input_class_num,
            "s3_key": c.s3_key,
            "created_at": c.created_at.isoformat() if c.created_at else None,
        })
    return result


@router.post("/captures/{capture_id}/approve", status_code=status.HTTP_204_NO_CONTENT)
async def approve_capture(
    capture_id: int,
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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


@router.post("/users/{user_id}/warn", status_code=status.HTTP_204_NO_CONTENT)
async def warn_user(
    user_id: int,
    req: WarnRequest,
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
    admin: AdminUser = Depends(_get_admin),
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
