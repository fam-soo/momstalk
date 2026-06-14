from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.service_models import Comment, Like, Post, User
from app.schemas.comment import CommentCreate, CommentResponse


async def create_comment(
    user: User,
    post_id: int,
    req: CommentCreate,
    db: AsyncSession,
) -> CommentResponse:
    comment = Comment(
        post_id=post_id,
        author_id=user.id,
        parent_id=req.parent_id,
        content=req.content,
        is_anonymous=req.is_anonymous,
    )
    db.add(comment)
    await db.commit()
    await db.refresh(comment)
    return CommentResponse(
        id=comment.id,
        post_id=comment.post_id,
        parent_id=comment.parent_id,
        content=comment.content,
        is_anonymous=comment.is_anonymous,
        like_count=comment.like_count,
        is_hidden=comment.is_hidden,
        is_post_author=False,  # 방금 작성한 댓글은 post_author 별도 체크 불필요
        is_liked=False,
        created_at=comment.created_at,
    )


async def list_comments(post_id: int, user: User, db: AsyncSession) -> list[CommentResponse]:
    # 게시글 작성자 ID 조회 (작성자 뱃지 판별용)
    post_result = await db.execute(select(Post).where(Post.id == post_id))
    post = post_result.scalar_one_or_none()
    post_author_id = post.author_id if post else None

    comments_result = await db.execute(
        select(Comment)
        .where(Comment.post_id == post_id, Comment.is_hidden == False)
        .order_by(Comment.created_at.asc())
    )
    comments = comments_result.scalars().all()

    # 현재 유저의 댓글 좋아요 여부 일괄 조회
    comment_ids = [c.id for c in comments]
    liked_ids: set[int] = set()
    if comment_ids:
        likes_result = await db.execute(
            select(Like.target_id).where(
                Like.user_id == user.id,
                Like.target_type == "comment",
                Like.target_id.in_(comment_ids),
            )
        )
        liked_ids = {row for row in likes_result.scalars()}

    return [
        CommentResponse(
            id=c.id,
            post_id=c.post_id,
            parent_id=c.parent_id,
            content=c.content,
            is_anonymous=c.is_anonymous,
            like_count=c.like_count,
            is_hidden=c.is_hidden,
            is_post_author=(c.author_id == post_author_id),  # ★ 작성자 뱃지
            is_liked=(c.id in liked_ids),
            created_at=c.created_at,
        )
        for c in comments
    ]


async def delete_comment(comment: Comment, db: AsyncSession) -> None:
    comment.is_deleted = True
    await db.commit()


async def toggle_like_comment(comment_id: int, user: User, db: AsyncSession) -> dict:
    """댓글 좋아요 토글. DB 레벨 UNIQUE 제약으로 중복 방지."""
    result = await db.execute(select(Comment).where(Comment.id == comment_id))
    comment = result.scalar_one_or_none()
    if not comment:
        raise ValueError("댓글을 찾을 수 없습니다.")

    existing = await db.execute(
        select(Like).where(Like.user_id == user.id, Like.target_type == "comment", Like.target_id == comment_id)
    )
    like = existing.scalar_one_or_none()

    if like:
        await db.delete(like)
        comment.like_count = max(0, comment.like_count - 1)
        liked = False
    else:
        db.add(Like(user_id=user.id, target_type="comment", target_id=comment_id))
        comment.like_count += 1
        liked = True

    await db.commit()
    return {"like_count": comment.like_count, "is_liked": liked}
