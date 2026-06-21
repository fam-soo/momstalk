from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_service_db
from app.models.service_models import User
from app.models.service_models import Comment
from app.schemas.comment import CommentCreate, CommentResponse, ReportRequest
from app.schemas.post import PostCreate, PostListItem, PostResponse, PostUpdate, ScrapResponse
from app.services import comment_service, post_service

router = APIRouter(prefix="/posts", tags=["posts"])


@router.get("", response_model=list[PostListItem])
async def list_posts(
    board_type: str = Query(..., description="grade / school / free / region"),
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    q: str = Query(None, description="검색어 (제목+내용)"),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """게시판별 게시글 목록. 유저의 학교/학년 기준으로 접근 범위 자동 제한."""
    return await post_service.list_posts(
        board_type=board_type,
        school_code=user.school_code,
        grade=user.grade,
        class_num=user.class_num,
        page=page,
        size=size,
        user=user,
        db=db,
        q=q,
    )


@router.post("", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_post(
    req: PostCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    try:
        post = await post_service.create_post(user, req, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return await post_service.get_post_response(post, user, db)


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
    post = await post_service.update_post(post, req, db)
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
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    try:
        return await comment_service.create_comment(user, post_id, req, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))


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
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """게시글/댓글 신고. 누적 5회 시 자동 블라인드. 중복 신고 불가."""
    try:
        await post_service.report_content(user, req.target_type, req.target_id, req.category, req.reason, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
