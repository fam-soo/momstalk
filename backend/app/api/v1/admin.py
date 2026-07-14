"""
관리자 API

인증: 일반 유저 JWT + users.is_admin = true
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc, or_, cast, String

from app.db import get_service_db
from app.models.service_models import (
    Academy,
    AcademyReview,
    AdminAction,
    AuthCapture,
    Comment,
    Post,
    ProfanityWord,
    Report,
    School,
    User,
    UserChild,
    UserWarning,
)
from app.services import capture_service
from app.services.school_unlock_service import get_unlock_status
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
        result.append({
            "id": c.id,
            "user_id": c.user_id,
            "nickname": user.nickname if user else None,
            "input_school_code": c.input_school_code,
            "input_school_name": c.input_school_name,
            "input_grade": c.input_grade,
            "input_class_num": c.input_class_num,
            "input_school_type": c.input_school_type,
            "input_region": c.input_region,
            "capture_type": c.capture_type if hasattr(c, "capture_type") else "initial",
            "has_image": bool(c.image_data),
            "created_at": c.created_at.isoformat() if c.created_at else None,
        })
    return result


@router.get("/captures/{capture_id}/image")
async def capture_image(
    capture_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    """DB에 저장된 캡처 이미지를 바로 반환 (외부 스토리지 왕복 없음)."""
    capture = (await db.execute(
        select(AuthCapture).where(AuthCapture.id == capture_id)
    )).scalar_one_or_none()
    if not capture or not capture.image_data:
        raise HTTPException(status_code=404, detail="이미지를 찾을 수 없습니다. 이미 심사 처리되었을 수 있습니다.")

    return Response(
        content=capture.image_data,
        media_type=capture.image_content_type or "image/jpeg",
        headers={"Cache-Control": "private, max-age=3600"},
    )


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
    from sqlalchemy import or_, cast, String

    post_count_subq = (
        select(func.count(Post.id))
        .where(Post.author_id == User.id, Post.is_deleted == False)
        .correlate(User)
        .scalar_subquery()
    )
    like_count_subq = (
        select(func.coalesce(func.sum(Post.like_count), 0))
        .where(Post.author_id == User.id, Post.is_deleted == False)
        .correlate(User)
        .scalar_subquery()
    )

    base = select(User, post_count_subq.label("post_count"), like_count_subq.label("like_count"))
    if q:
        query = base.where(
            or_(
                User.nickname.ilike(f"%{q}%"),
                cast(User.id, String) == q,
                User.kakao_id == q,
            )
        ).order_by(User.created_at.desc()).limit(50)
    else:
        query = base.where(User.is_admin == False).order_by(User.created_at.desc()).limit(100)
    rows = (await db.execute(query)).all()
    return [
        {
            "id": u.id,
            "nickname": u.nickname,
            "school_name": u.school_name,
            "grade": u.grade,
            # 다자녀 계정은 등록된 자녀 수만큼 학교가 있을 수 있다. 위 school_name/
            # grade는 "첫 자녀 등록 시"에만 동기화되는 레거시 필드라 다자녀·학교
            # 변경 계정에서는 실제와 어긋난다 — 화면에서는 children을 우선 쓸 것.
            "children": [
                {
                    "id": c.id,
                    "school_name": c.school_name,
                    "grade": c.grade,
                    "school_type": c.school_type,
                    "is_active": c.id == u.active_child_id,
                }
                for c in u.children
            ],
            "member_grade": u.member_grade,
            "is_banned": u.is_banned,
            "is_trusted": u.is_trusted,
            "kakao_id": u.kakao_id,
            "suspended_until": u.suspended_until.isoformat() if u.suspended_until else None,
            "warning_count": u.warning_count,
            "post_count": post_count,
            "like_count": like_count,
            "last_login_at": u.last_login_at.isoformat() if u.last_login_at else None,
            "login_count": u.login_count or 0,
            "created_at": u.created_at.isoformat() if u.created_at else None,
        }
        for u, post_count, like_count in rows
    ]


@router.get("/schools/name-check")
async def school_name_check(
    name: str = Query(..., min_length=2),
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    """같은 이름의 학교가 school_code만 다르게 여러 개 등록돼 있는지 점검한다.

    schools.school_code는 UNIQUE지만 school_name은 아니라서, NEIS 데이터에
    같은 이름의 학교가 지역별로 서로 다른 코드로 여러 개 존재할 수 있다.
    검색해서 다른 학교를 고른 학부모끼리는 UserChild.school_code가 갈리기
    때문에, 관리자 유저 목록에서 이름만 보고 센 인원과 특정 코드 하나만
    보는 언락/대시보드 인원이 서로 다르게 보이는 원인이 될 수 있다.
    """
    schools = (await db.execute(
        select(School).where(School.school_name == name)
    )).scalars().all()

    result = []
    for s in schools:
        member_count = (await db.execute(
            select(func.count(func.distinct(UserChild.user_id)))
            .join(User, User.id == UserChild.user_id)
            .where(UserChild.school_code == s.school_code, User.member_grade == "member", User.is_admin.is_(False))
        )).scalar() or 0
        total_registered = (await db.execute(
            select(func.count(func.distinct(UserChild.user_id)))
            .join(User, User.id == UserChild.user_id)
            .where(UserChild.school_code == s.school_code, User.is_admin.is_(False))
        )).scalar() or 0
        result.append({
            "school_code": s.school_code,
            "school_name": s.school_name,
            "address": s.address,
            "region": s.region,
            "member_count": member_count,
            "total_registered": total_registered,
        })
    return {"count": len(result), "schools": result}


@router.get("/schools/{school_code}/members")
async def school_members(
    school_code: str,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    """해당 학교 학교게시판 언락 화면과 '동일한 기준'으로 정회원 명단을 보여준다.

    이전에는 관리자 화면이 유저의 레거시 users.school_name(다자녀 시 첫 자녀
    등록 때만 동기화되어 자녀 전환 후에는 실제 소속 학교와 어긋날 수 있음)을
    기준으로 학교별 인원을 눈대중으로 셌기 때문에, UserChild.school_code
    기준으로 계산하는 언락 화면의 인원수와 서로 달라 보이는 문제가 있었다.
    같은 school_unlock_service.get_unlock_status()를 그대로 사용하고, 명단도
    동일한 필터(UserChild.school_code + member_grade='member' + 관리자 제외)로
    조회해 두 화면의 숫자가 항상 일치하도록 한다.

    학교 언락 인원(member_count)은 "정회원"만 세므로, 캡처 인증 대기 중인
    lurker까지 포함한 "전체 가입(자녀 등록)" 수와는 의도적으로 다를 수 있다
    — 아무나 학교명만 입력해도 언락 인원에 잡히면 인증 문턱의 의미가 없어지기
    때문. 두 숫자를 둘 다 보여줘서 혼동을 없앤다.
    """
    unlock = await get_unlock_status(school_code, db)

    total_registered = (await db.execute(
        select(func.count(func.distinct(UserChild.user_id)))
        .join(User, User.id == UserChild.user_id)
        .where(UserChild.school_code == school_code, User.is_admin.is_(False))
    )).scalar() or 0

    post_count_subq = (
        select(func.count(Post.id))
        .where(Post.author_id == User.id, Post.is_deleted == False)
        .correlate(User)
        .scalar_subquery()
    )
    like_count_subq = (
        select(func.coalesce(func.sum(Post.like_count), 0))
        .where(Post.author_id == User.id, Post.is_deleted == False)
        .correlate(User)
        .scalar_subquery()
    )
    query = (
        select(User, post_count_subq.label("post_count"), like_count_subq.label("like_count"))
        .join(UserChild, UserChild.user_id == User.id)
        .where(
            UserChild.school_code == school_code,
            User.member_grade == "member",
            User.is_admin.is_(False),
        )
        .distinct()
        .order_by(User.created_at.desc())
    )
    rows = (await db.execute(query)).all()
    return {
        **unlock,
        "total_registered": total_registered,
        "users": [
            {
                "id": u.id,
                "nickname": u.nickname,
                "school_name": u.school_name,
                "grade": u.grade,
                "children": [
                    {
                        "id": c.id,
                        "school_name": c.school_name,
                        "grade": c.grade,
                        "school_type": c.school_type,
                        "is_active": c.id == u.active_child_id,
                    }
                    for c in u.children
                ],
                "member_grade": u.member_grade,
                "is_banned": u.is_banned,
                "is_trusted": u.is_trusted,
                "kakao_id": u.kakao_id,
                "post_count": post_count,
                "like_count": like_count,
                "last_login_at": u.last_login_at.isoformat() if u.last_login_at else None,
                "login_count": u.login_count or 0,
                "created_at": u.created_at.isoformat() if u.created_at else None,
            }
            for u, post_count, like_count in rows
        ],
    }


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
    like_count = (await db.execute(
        select(func.coalesce(func.sum(Post.like_count), 0)).where(Post.author_id == user_id, Post.is_deleted == False)
    )).scalar()
    return {
        "id": user.id,
        "nickname": user.nickname,
        "school_name": user.school_name,
        "grade": user.grade,
        "children": [
            {
                "id": c.id,
                "school_name": c.school_name,
                "grade": c.grade,
                "school_type": c.school_type,
                "is_active": c.id == user.active_child_id,
            }
            for c in user.children
        ],
        "member_grade": user.member_grade,
        "is_banned": user.is_banned,
        "is_trusted": user.is_trusted,
        "kakao_id": user.kakao_id,
        "suspended_until": user.suspended_until.isoformat() if user.suspended_until else None,
        "warning_count": user.warning_count,
        "post_count": post_count,
        "like_count": like_count,
        "last_login_at": user.last_login_at.isoformat() if user.last_login_at else None,
        "login_count": user.login_count or 0,
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


@router.post("/users/{user_id}/grant-trust", status_code=status.HTTP_204_NO_CONTENT)
async def grant_trust(
    user_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    """자녀 추가·인증 심사 면제 권한 부여. 부여된 사용자는 캡처 제출 시 자동 승인."""
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다.")
    user.is_trusted = True
    db.add(AdminAction(admin_id=admin.id, action_type="grant_trust", target_type="user", target_id=user_id))
    await db.commit()


@router.post("/users/{user_id}/revoke-trust", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_trust(
    user_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    """자녀 추가·인증 심사 면제 권한 해제."""
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다.")
    user.is_trusted = False
    db.add(AdminAction(admin_id=admin.id, action_type="revoke_trust", target_type="user", target_id=user_id))
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


# ── 통계 대시보드 ──────────────────────────────────────

@router.get("/stats")
async def get_stats(
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    now = datetime.utcnow()
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_ago = now - timedelta(days=7)

    total_users = (await db.execute(select(func.count(User.id)))).scalar()
    member_count = (await db.execute(
        select(func.count(User.id)).where(User.member_grade == "member")
    )).scalar()
    lurker_count = (await db.execute(
        select(func.count(User.id)).where(User.member_grade == "lurker")
    )).scalar()
    banned_count = (await db.execute(
        select(func.count(User.id)).where(User.is_banned == True)
    )).scalar()
    suspended_count = (await db.execute(
        select(func.count(User.id)).where(User.suspended_until > now)
    )).scalar()
    new_today = (await db.execute(
        select(func.count(User.id)).where(User.created_at >= today)
    )).scalar()
    new_week = (await db.execute(
        select(func.count(User.id)).where(User.created_at >= week_ago)
    )).scalar()

    pending_captures = (await db.execute(
        select(func.count(AuthCapture.id)).where(AuthCapture.status == "pending")
    )).scalar()
    pending_reports = (await db.execute(
        select(func.count(Report.id)).where(Report.status == "pending")
    )).scalar()

    total_posts = (await db.execute(
        select(func.count(Post.id)).where(Post.is_deleted == False)
    )).scalar()
    posts_today = (await db.execute(
        select(func.count(Post.id)).where(Post.created_at >= today, Post.is_deleted == False)
    )).scalar()
    posts_week = (await db.execute(
        select(func.count(Post.id)).where(Post.created_at >= week_ago, Post.is_deleted == False)
    )).scalar()
    hidden_posts = (await db.execute(
        select(func.count(Post.id)).where(Post.is_hidden == True, Post.is_deleted == False)
    )).scalar()

    total_reviews = (await db.execute(
        select(func.count(AcademyReview.id)).where(AcademyReview.is_seed == False)
    )).scalar()
    hidden_reviews = (await db.execute(
        select(func.count(AcademyReview.id)).where(
            AcademyReview.is_hidden == True, AcademyReview.is_seed == False
        )
    )).scalar()

    from sqlalchemy import text
    daily_rows = (await db.execute(text(
        "SELECT DATE(created_at) as d, COUNT(*) as cnt "
        "FROM users WHERE created_at >= NOW() - INTERVAL '7 days' "
        "GROUP BY d ORDER BY d"
    ))).fetchall()
    daily_signup = [{"date": str(r.d), "count": r.cnt} for r in daily_rows]

    daily_post_rows = (await db.execute(text(
        "SELECT DATE(created_at) as d, COUNT(*) as cnt "
        "FROM posts WHERE created_at >= NOW() - INTERVAL '7 days' AND is_deleted = false "
        "GROUP BY d ORDER BY d"
    ))).fetchall()
    daily_posts = [{"date": str(r.d), "count": r.cnt} for r in daily_post_rows]

    # 학교별 정회원 수 — 학교 게시판 언락 화면(count_school_members)·관리자
    # "학교별 인원 조회"와 정확히 같은 그룹 기준(UserChild.school_code +
    # member_grade='member', 관리자 제외)으로 집계한다. 예전엔 School.school_name
    # 으로 GROUP BY 했는데, school_code가 아닌 이름 기준이라 이론상 동명 학교가
    # 있으면 다른 화면과 숫자가 어긋날 수 있었다 — code 기준으로 통일.
    school_rows = (await db.execute(
        select(UserChild.school_code, func.count(func.distinct(UserChild.user_id)).label("cnt"))
        .join(User, User.id == UserChild.user_id)
        .where(User.member_grade == "member", User.is_admin.is_(False), UserChild.school_code.isnot(None))
        .group_by(UserChild.school_code)
        .order_by(func.count(func.distinct(UserChild.user_id)).desc())
        .limit(10)
    )).all()
    _school_codes = [r.school_code for r in school_rows]
    _school_names = dict((await db.execute(
        select(School.school_code, School.school_name).where(School.school_code.in_(_school_codes))
    )).all()) if _school_codes else {}
    by_school = [
        {"school_name": _school_names.get(r.school_code, r.school_code), "member_count": r.cnt}
        for r in school_rows
    ]

    return {
        "users": {
            "total": total_users,
            "member": member_count,
            "lurker": lurker_count,
            "banned": banned_count,
            "suspended": suspended_count,
            "new_today": new_today,
            "new_week": new_week,
        },
        "pending": {
            "captures": pending_captures,
            "reports": pending_reports,
        },
        "posts": {
            "total": total_posts,
            "today": posts_today,
            "week": posts_week,
            "hidden": hidden_posts,
        },
        "reviews": {
            "total": total_reviews,
            "hidden": hidden_reviews,
        },
        "daily_signup": daily_signup,
        "daily_posts": daily_posts,
        "by_school": by_school,
    }


# ── 게시글 목록 (관리자용) ─────────────────────────────

@router.get("/posts")
async def list_posts_admin(
    q: Optional[str] = Query(None),
    filter: str = Query("all"),
    page: int = Query(1, ge=1),
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    limit = 30
    offset = (page - 1) * limit
    query = select(Post).where(Post.is_deleted == False)
    if filter == "hidden":
        query = query.where(Post.is_hidden == True)
    elif filter == "reported":
        reported_ids = (await db.execute(
            select(Report.target_id).where(Report.target_type == "post", Report.status == "pending")
        )).scalars().all()
        query = query.where(Post.id.in_(reported_ids))
    if q:
        query = query.where(or_(Post.title.ilike(f"%{q}%"), Post.content.ilike(f"%{q}%")))
    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar()
    posts = (await db.execute(query.order_by(desc(Post.created_at)).limit(limit).offset(offset))).scalars().all()
    author_ids = list({p.author_id for p in posts if p.author_id})
    authors: dict[int, str] = {}
    if author_ids:
        for u in (await db.execute(select(User).where(User.id.in_(author_ids)))).scalars().all():
            authors[u.id] = u.nickname or "?"
    return {
        "total": total,
        "page": page,
        "items": [
            {
                "id": p.id,
                "title": p.title,
                "content": (p.content or "")[:100],
                "board_type": p.board_type,
                "author_nickname": authors.get(p.author_id, "알수없음"),
                "author_id": p.author_id,
                "is_hidden": p.is_hidden,
                "report_count": p.report_count,
                "created_at": p.created_at.isoformat() if p.created_at else None,
            }
            for p in posts
        ],
    }


# ── 댓글 관리 ──────────────────────────────────────────

@router.get("/comments")
async def list_comments_admin(
    q: Optional[str] = Query(None),
    filter: str = Query("all"),
    page: int = Query(1, ge=1),
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    limit = 30
    offset = (page - 1) * limit
    query = select(Comment).where(Comment.is_deleted == False)
    if filter == "hidden":
        query = query.where(Comment.is_hidden == True)
    elif filter == "reported":
        reported_ids = (await db.execute(
            select(Report.target_id).where(Report.target_type == "comment", Report.status == "pending")
        )).scalars().all()
        query = query.where(Comment.id.in_(reported_ids))
    if q:
        query = query.where(Comment.content.ilike(f"%{q}%"))
    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar()
    comments = (await db.execute(query.order_by(desc(Comment.created_at)).limit(limit).offset(offset))).scalars().all()
    author_ids = list({c.author_id for c in comments if c.author_id})
    authors: dict[int, str] = {}
    if author_ids:
        for u in (await db.execute(select(User).where(User.id.in_(author_ids)))).scalars().all():
            authors[u.id] = u.nickname or "?"
    return {
        "total": total,
        "page": page,
        "items": [
            {
                "id": c.id,
                "content": (c.content or "")[:200],
                "post_id": c.post_id,
                "author_nickname": authors.get(c.author_id, "알수없음"),
                "author_id": c.author_id,
                "is_hidden": c.is_hidden,
                "report_count": c.report_count,
                "created_at": c.created_at.isoformat() if c.created_at else None,
            }
            for c in comments
        ],
    }


@router.post("/comments/{comment_id}/hide", status_code=status.HTTP_204_NO_CONTENT)
async def hide_comment(
    comment_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    comment = (await db.execute(select(Comment).where(Comment.id == comment_id))).scalar_one_or_none()
    if not comment:
        raise HTTPException(status_code=404, detail="댓글을 찾을 수 없습니다.")
    comment.is_hidden = True
    db.add(AdminAction(admin_id=admin.id, action_type="hide_comment", target_type="comment", target_id=comment_id))
    await db.commit()


@router.post("/comments/{comment_id}/unhide", status_code=status.HTTP_204_NO_CONTENT)
async def unhide_comment(
    comment_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    comment = (await db.execute(select(Comment).where(Comment.id == comment_id))).scalar_one_or_none()
    if not comment:
        raise HTTPException(status_code=404, detail="댓글을 찾을 수 없습니다.")
    comment.is_hidden = False
    db.add(AdminAction(admin_id=admin.id, action_type="unhide_comment", target_type="comment", target_id=comment_id))
    await db.commit()


@router.delete("/comments/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def force_delete_comment(
    comment_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    comment = (await db.execute(select(Comment).where(Comment.id == comment_id))).scalar_one_or_none()
    if not comment:
        raise HTTPException(status_code=404, detail="댓글을 찾을 수 없습니다.")
    comment.is_deleted = True
    comment.is_hidden = True
    db.add(AdminAction(admin_id=admin.id, action_type="delete_comment", target_type="comment", target_id=comment_id))
    await db.commit()


# ── 학원 후기 관리 ────────────────────────────────────

@router.get("/reviews")
async def list_reviews_admin(
    q: Optional[str] = Query(None),
    filter: str = Query("all"),
    page: int = Query(1, ge=1),
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    limit = 30
    offset = (page - 1) * limit
    query = select(AcademyReview)
    if filter == "hidden":
        query = query.where(AcademyReview.is_hidden == True)
    elif filter == "seed":
        query = query.where(AcademyReview.is_seed == True)
    elif filter == "user":
        query = query.where(AcademyReview.is_seed == False)
    if q:
        query = query.where(AcademyReview.review_text.ilike(f"%{q}%"))
    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar()
    reviews = (await db.execute(query.order_by(desc(AcademyReview.created_at)).limit(limit).offset(offset))).scalars().all()
    academy_ids = list({r.academy_id for r in reviews})
    academies: dict[int, str] = {}
    if academy_ids:
        for a in (await db.execute(select(Academy).where(Academy.id.in_(academy_ids)))).scalars().all():
            academies[a.id] = a.name
    author_ids = list({r.author_id for r in reviews if r.author_id})
    authors: dict[int, str] = {}
    if author_ids:
        for u in (await db.execute(select(User).where(User.id.in_(author_ids)))).scalars().all():
            authors[u.id] = u.nickname or "?"
    return {
        "total": total,
        "page": page,
        "items": [
            {
                "id": r.id,
                "academy_id": r.academy_id,
                "academy_name": academies.get(r.academy_id, "?"),
                "author_nickname": authors.get(r.author_id, "알수없음"),
                "author_id": r.author_id,
                "rating": r.rating,
                "review_text": (r.review_text or "")[:200],
                "is_hidden": r.is_hidden,
                "is_seed": r.is_seed,
                "report_count": r.report_count,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in reviews
        ],
    }


@router.post("/reviews/{review_id}/hide", status_code=status.HTTP_204_NO_CONTENT)
async def hide_review(
    review_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    review = (await db.execute(select(AcademyReview).where(AcademyReview.id == review_id))).scalar_one_or_none()
    if not review:
        raise HTTPException(status_code=404, detail="후기를 찾을 수 없습니다.")
    review.is_hidden = True
    db.add(AdminAction(admin_id=admin.id, action_type="hide_review", target_type="review", target_id=review_id))
    await db.commit()


@router.post("/reviews/{review_id}/unhide", status_code=status.HTTP_204_NO_CONTENT)
async def unhide_review(
    review_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    review = (await db.execute(select(AcademyReview).where(AcademyReview.id == review_id))).scalar_one_or_none()
    if not review:
        raise HTTPException(status_code=404, detail="후기를 찾을 수 없습니다.")
    review.is_hidden = False
    db.add(AdminAction(admin_id=admin.id, action_type="unhide_review", target_type="review", target_id=review_id))
    await db.commit()


@router.delete("/reviews/{review_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_review_admin(
    review_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    review = (await db.execute(select(AcademyReview).where(AcademyReview.id == review_id))).scalar_one_or_none()
    if not review:
        raise HTTPException(status_code=404, detail="후기를 찾을 수 없습니다.")
    await db.delete(review)
    db.add(AdminAction(admin_id=admin.id, action_type="delete_review", target_type="review", target_id=review_id))
    await db.commit()


# ── 금칙어 관리 ───────────────────────────────────────

@router.get("/profanity")
async def list_profanity(
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    words = (await db.execute(select(ProfanityWord).order_by(ProfanityWord.word))).scalars().all()
    return [{"id": w.id, "word": w.word, "created_at": w.created_at.isoformat() if w.created_at else None} for w in words]


class ProfanityRequest(BaseModel):
    word: str


@router.post("/profanity", status_code=status.HTTP_201_CREATED)
async def add_profanity(
    req: ProfanityRequest,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    word = req.word.strip().lower()
    if not word:
        raise HTTPException(status_code=400, detail="단어를 입력해주세요.")
    existing = (await db.execute(select(ProfanityWord).where(ProfanityWord.word == word))).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=409, detail="이미 등록된 금칙어입니다.")
    db.add(ProfanityWord(word=word))
    db.add(AdminAction(admin_id=admin.id, action_type="add_profanity", detail=word))
    await db.commit()
    return {"word": word}


class ProfanityBulkRequest(BaseModel):
    words: str  # 쉼표(또는 줄바꿈)로 구분된 여러 단어


@router.post("/profanity/bulk", status_code=status.HTTP_201_CREATED)
async def add_profanity_bulk(
    req: ProfanityBulkRequest,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    """쉼표(,) 또는 줄바꿈으로 구분된 여러 단어를 한 번에 등록.
    하나씩 등록하기 번거롭다는 피드백 반영 — 이미 등록된 단어는 조용히 건너뛴다."""
    raw_words = [w.strip().lower() for w in req.words.replace("\n", ",").split(",")]
    candidates = list(dict.fromkeys(w for w in raw_words if w))  # 순서 유지 + 중복 제거
    if not candidates:
        raise HTTPException(status_code=400, detail="등록할 단어가 없습니다.")

    existing_rows = (await db.execute(
        select(ProfanityWord.word).where(ProfanityWord.word.in_(candidates))
    )).scalars().all()
    existing_set = set(existing_rows)
    new_words = [w for w in candidates if w not in existing_set]

    for w in new_words:
        db.add(ProfanityWord(word=w))
    if new_words:
        db.add(AdminAction(
            admin_id=admin.id, action_type="add_profanity_bulk",
            detail=f"{len(new_words)}개 추가: {', '.join(new_words[:20])}{' 외' if len(new_words) > 20 else ''}",
        ))
        await db.commit()
    return {"added": len(new_words), "skipped": len(candidates) - len(new_words), "words": new_words}


@router.patch("/profanity/{word_id}")
async def update_profanity(
    word_id: int,
    req: ProfanityRequest,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    new_word = req.word.strip().lower()
    if not new_word:
        raise HTTPException(status_code=400, detail="단어를 입력해주세요.")
    word = (await db.execute(select(ProfanityWord).where(ProfanityWord.id == word_id))).scalar_one_or_none()
    if not word:
        raise HTTPException(status_code=404, detail="금칙어를 찾을 수 없습니다.")
    if new_word != word.word:
        existing = (await db.execute(
            select(ProfanityWord).where(ProfanityWord.word == new_word, ProfanityWord.id != word_id)
        )).scalar_one_or_none()
        if existing:
            raise HTTPException(status_code=409, detail="이미 등록된 금칙어입니다.")
        db.add(AdminAction(admin_id=admin.id, action_type="edit_profanity", detail=f"{word.word} → {new_word}"))
        word.word = new_word
        await db.commit()
    return {"id": word.id, "word": word.word}


@router.delete("/profanity/{word_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_profanity(
    word_id: int,
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    word = (await db.execute(select(ProfanityWord).where(ProfanityWord.id == word_id))).scalar_one_or_none()
    if not word:
        raise HTTPException(status_code=404, detail="금칙어를 찾을 수 없습니다.")
    db.add(AdminAction(admin_id=admin.id, action_type="delete_profanity", detail=word.word))
    await db.delete(word)
    await db.commit()


# ── 관리자 행동 로그 ───────────────────────────────────

@router.get("/logs")
async def list_admin_logs(
    page: int = Query(1, ge=1),
    admin: User = Depends(_require_admin),
    db: AsyncSession = Depends(get_service_db),
):
    limit = 50
    offset = (page - 1) * limit
    total = (await db.execute(select(func.count(AdminAction.id)))).scalar()
    logs = (await db.execute(
        select(AdminAction).order_by(desc(AdminAction.created_at)).limit(limit).offset(offset)
    )).scalars().all()
    admin_ids = list({log.admin_id for log in logs if log.admin_id})
    admins: dict[int, str] = {}
    if admin_ids:
        for u in (await db.execute(select(User).where(User.id.in_(admin_ids)))).scalars().all():
            admins[u.id] = u.nickname or "?"
    return {
        "total": total,
        "page": page,
        "items": [
            {
                "id": log.id,
                "admin_nickname": admins.get(log.admin_id, "?"),
                "action_type": log.action_type,
                "target_type": log.target_type,
                "target_id": log.target_id,
                "detail": log.detail,
                "created_at": log.created_at.isoformat() if log.created_at else None,
            }
            for log in logs
        ],
    }
