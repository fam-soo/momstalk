from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.rate_limit import RateLimit
from app.db import get_service_db
from app.models.service_models import User
from app.models.service_models import Comment
from app.schemas.comment import CommentCreate, CommentResponse, ReportRequest
from app.schemas.post import PostCreate, PostListItem, PostListResponse, PostResponse, PostUpdate, ScrapResponse
from app.services import comment_service, post_service

router = APIRouter(prefix="/posts", tags=["posts"])


@router.get("", response_model=PostListResponse)
async def list_posts(
    board_type: str = Query(..., description="grade / school / free / region"),
    size: int = Query(20, ge=1, le=100),
    cursor: int = Query(None, description="이전 응답의 next_cursor 값 (첫 페이지는 생략)"),
    sort: str = Query("recent", description="recent | popular"),
    q: str = Query(None, description="검색어 (제목+내용)"),
    child_id: int = Query(None, description="다자녀 조회 시 특정 자녀의 학교 보기. 본인 자녀만 허용."),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """게시판별 게시글 목록. cursor 기반 무한 스크롤."""
    from sqlalchemy import select as sa_select
    from app.models.service_models import UserChild

    if child_id is not None:
        # 보안: 요청한 child_id가 본인 자녀인지 확인
        child = (await db.execute(
            sa_select(UserChild).where(UserChild.id == child_id, UserChild.user_id == user.id)
        )).scalar_one_or_none()
        if child:
            school_code = child.school_code
            grade = child.grade
            class_num = child.class_num
        else:
            active = user.active_child
            school_code = (active.school_code if active else None) or user.school_code
            grade = (active.grade if active else None) or user.grade
            class_num = (active.class_num if active else None) or user.class_num
    else:
        active = user.active_child
        school_code = (active.school_code if active else None) or user.school_code
        grade = (active.grade if active else None) or user.grade
        class_num = (active.class_num if active else None) or user.class_num

    try:
        return await post_service.list_posts(
            board_type=board_type,
            school_code=school_code,
            grade=grade,
            class_num=class_num,
            size=size,
            user=user,
            db=db,
            q=q,
            sort=sort,
            cursor=cursor,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))


@router.post("", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_post(
    req: PostCreate,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    await RateLimit.post_create(request)
    try:
        post = await post_service.create_post(user, req, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return await post_service.get_post_response(post, user, db)


@router.get("/notices")
async def get_notices(db: AsyncSession = Depends(get_service_db)):
    """공지사항 목록 (인증 불필요). 지역 게시판 상단 고정 및 첫 로그인 팝업용."""
    from sqlalchemy import select as sa_select
    from app.models.service_models import Post as PostModel

    stmt = (
        sa_select(PostModel)
        .where(PostModel.board_type == "notice", PostModel.is_hidden == False, PostModel.is_deleted == False)  # noqa: E712
        .order_by(PostModel.created_at.desc())
        .limit(5)
    )
    result = await db.execute(stmt)
    posts = result.scalars().all()
    return [
        {
            "id": p.id,
            "title": p.title,
            "content": p.content,
            "created_at": p.created_at.isoformat() if p.created_at else None,
        }
        for p in posts
    ]


@router.get("/preview")
async def preview_posts(
    board_type: str = Query("region", description="region | school | free"),
    db: AsyncSession = Depends(get_service_db),
):
    """비회원 미리보기: 인기글 5개 (인증 불필요)."""
    from sqlalchemy import select, text
    from app.models.service_models import Post as PostModel

    stmt = (
        select(PostModel)
        .where(
            PostModel.board_type == board_type,
            PostModel.is_hidden == False,  # noqa: E712
            PostModel.is_deleted == False,  # noqa: E712
        )
        .order_by((PostModel.like_count + PostModel.view_count).desc(), PostModel.created_at.desc())
        .limit(5)
    )
    result = await db.execute(stmt)
    posts = result.scalars().all()
    return [
        {
            "id": p.id,
            "title": p.title,
            "like_count": p.like_count,
            "view_count": p.view_count,
            "created_at": p.created_at.isoformat() if p.created_at else None,
        }
        for p in posts
    ]


@router.get("/me/scraps", response_model=list[ScrapResponse])
async def my_scraps(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """내가 스크랩한 게시글 목록."""
    return await post_service.list_scraps(user, db)


@router.get("/{post_id}", response_model=PostResponse)
async def get_post(
    post_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    post = await post_service.get_post(post_id, db)
    if not post or post.is_hidden or post.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="게시글을 찾을 수 없습니다.")
    return await post_service.get_post_response(post, user, db)


@router.patch("/{post_id}", response_model=PostResponse)
async def update_post(
    post_id: int,
    req: PostUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    post = await post_service.get_post(post_id, db)
    if not post or post.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="게시글을 찾을 수 없습니다.")
    if post.author_id != user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="본인의 게시글만 수정할 수 있습니다.")
    try:
        post = await post_service.update_post(post, req, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return await post_service.get_post_response(post, user, db)


@router.delete("/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_post(
    post_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    post = await post_service.get_post(post_id, db)
    if not post or post.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="게시글을 찾을 수 없습니다.")
    if post.author_id != user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="본인의 게시글만 삭제할 수 있습니다.")
    await post_service.delete_post(post, db)


@router.post("/{post_id}/like")
async def like_post(
    post_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """좋아요 토글. 이미 눌렀으면 취소, 안 눌렀으면 추가."""
    try:
        return await post_service.toggle_like_post(post_id, user, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))


@router.post("/{post_id}/scrap")
async def scrap_post(
    post_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """스크랩 토글. 이미 했으면 취소, 안 했으면 추가."""
    try:
        return await post_service.toggle_scrap(post_id, user, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))


# ── 댓글 ────────────────────────────────────────────

@router.get("/{post_id}/comments", response_model=list[CommentResponse])
async def list_comments(
    post_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    return await comment_service.list_comments(post_id, user, db)


@router.post("/{post_id}/comments", response_model=CommentResponse, status_code=status.HTTP_201_CREATED)
async def create_comment(
    post_id: int,
    req: CommentCreate,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    await RateLimit.comment_create(request)
    try:
        return await comment_service.create_comment(user, post_id, req, db)
    except ValueError as e:
        msg = str(e)
        code = status.HTTP_404_NOT_FOUND if '찾을 수 없습니다' in msg else status.HTTP_400_BAD_REQUEST
        raise HTTPException(status_code=code, detail=msg)


@router.delete("/{post_id}/comments/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_comment(
    post_id: int,
    comment_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    from sqlalchemy import select as sa_select
    result = await db.execute(sa_select(Comment).where(Comment.id == comment_id, Comment.post_id == post_id))
    comment_obj = result.scalar_one_or_none()
    if not comment_obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="댓글을 찾을 수 없습니다.")
    if comment_obj.author_id != user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="본인의 댓글만 삭제할 수 있습니다.")
    await comment_service.delete_comment(comment_obj, db)


@router.post("/{post_id}/comments/{comment_id}/like")
async def like_comment(
    post_id: int,
    comment_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    try:
        return await comment_service.toggle_like_comment(comment_id, user, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))


# ── 신고 ────────────────────────────────────────────

@router.post("/report", status_code=status.HTTP_204_NO_CONTENT)
async def report(
    req: ReportRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """게시글/댓글 신고. 누적 5회 시 자동 블라인드. 중복 신고 불가."""
    await RateLimit.report(request)
    try:
        await post_service.report_content(user, req.target_type, req.target_id, req.category, req.reason, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
