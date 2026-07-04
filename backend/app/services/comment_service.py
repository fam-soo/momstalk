from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.fcm import send_push
from app.core.profanity import check_profanity
from app.models.service_models import Block, Comment, Like, Post, User
from app.schemas.comment import CommentCreate, CommentResponse
from app.services import temperature_service


async def create_comment(
    user: User,
    post_id: int,
    req: CommentCreate,
    db: AsyncSession,
) -> CommentResponse:
    post = (await db.execute(select(Post).where(Post.id == post_id))).scalar_one_or_none()
    if not post or post.is_deleted or post.is_hidden:
        raise ValueError("게시글을 찾을 수 없습니다.")

    check_profanity(req.content, "댓글")

    comment = Comment(
        post_id=post_id,
        author_id=user.id,
        parent_id=req.parent_id,
        content=req.content,
        is_anonymous=req.is_anonymous,
        nickname_type=req.nickname_type,
    )
    db.add(comment)
    await temperature_service.adjust(user.id, "comment_created", db)
    await db.commit()
    await db.refresh(comment)
    # 방금 작성한 댓글의 anon_label을 계산하기 위해 기존 댓글 목록 확인
    existing_result = await db.execute(
        select(Comment)
        .where(Comment.post_id == post_id, Comment.is_hidden == False)
        .order_by(Comment.created_at.asc())
    )
    all_comments = existing_result.scalars().all()
    post_obj = (await db.execute(select(Post).where(Post.id == post_id))).scalar_one_or_none()
    anon_labels = _build_anon_labels(all_comments, post_obj.author_id if post_obj else None)

    response = CommentResponse(
        id=comment.id,
        post_id=comment.post_id,
        parent_id=comment.parent_id,
        content=comment.content,
        is_anonymous=comment.is_anonymous,
        like_count=comment.like_count,
        is_hidden=comment.is_hidden,
        is_post_author=(post_obj is not None and comment.author_id == post_obj.author_id),
        is_liked=False,
        is_mine=True,
        anon_label=anon_labels.get(comment.author_id) if comment.is_anonymous else None,
        created_at=comment.created_at,
    )

    # 게시글 작성자에게 푸시 알림 (자기 글에 단 댓글은 제외)
    if post_obj and post_obj.author_id != user.id:
        post_author = (await db.execute(select(User).where(User.id == post_obj.author_id))).scalar_one_or_none()
        if post_author and post_author.fcm_token:
            label = anon_labels.get(user.id, "익명") if comment.is_anonymous else (user.nickname or "누군가")
            await send_push(
                post_author.fcm_token,
                title="새 댓글이 달렸어요",
                body=f"{label}: {comment.content[:50]}",
                data={"type": "comment", "post_id": str(post_id)},
            )

    return response


def _build_anon_labels(comments: list, post_author_id: int | None) -> dict[int, str]:
    """익명 댓글 작성자별 표시명 계산 (런타임, DB 저장 없음).

    게시글 작성자 → "글쓴이"
    그 외 익명 댓글 작성자 → 최초 등장 순서대로 "익명1", "익명2", ...
    """
    labels: dict[int, str] = {}
    counter = 0
    for c in sorted(comments, key=lambda x: x.created_at):
        if not c.is_anonymous:
            continue
        if c.author_id not in labels:
            if c.author_id == post_author_id:
                labels[c.author_id] = "글쓴이"
            else:
                counter += 1
                labels[c.author_id] = f"익명{counter}"
    return labels


async def list_comments(post_id: int, user: User, db: AsyncSession) -> list[CommentResponse]:
    # 게시글 작성자 ID 조회
    post_result = await db.execute(select(Post).where(Post.id == post_id))
    post = post_result.scalar_one_or_none()
    post_author_id = post.author_id if post else None

    # 차단한 유저의 댓글 제외
    blocked_result = await db.execute(select(Block.blocked_user_id).where(Block.user_id == user.id))
    blocked_ids = {r for r in blocked_result.scalars()}

    base_filter = [Comment.post_id == post_id, Comment.is_hidden == False]
    if blocked_ids:
        base_filter.append(Comment.author_id.notin_(blocked_ids))

    comments_result = await db.execute(
        select(Comment)
        .where(*base_filter)
        .order_by(Comment.created_at.asc())
    )
    comments = comments_result.scalars().all()

    # 스레드 익명화 레이블 계산
    anon_labels = _build_anon_labels(comments, post_author_id)

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

    # 댓글 작성자 일괄 조회 (nickname_type에 따라 적절한 닉네임 선택)
    all_author_ids = {c.author_id for c in comments}
    users_map: dict[int, User] = {}
    if all_author_ids:
        users_result = await db.execute(select(User).where(User.id.in_(all_author_ids)))
        for u in users_result.scalars():
            users_map[u.id] = u

    def _comment_display_name(c: Comment) -> str | None:
        author = users_map.get(c.author_id)
        if not author:
            return None
        if author.is_admin:
            return "관리자"
        if c.is_anonymous:
            return None
        nick_type = getattr(c, "nickname_type", "anon")
        if nick_type == "certified":
            return author.certified_nickname or author.nickname
        return author.nickname

    return [
        CommentResponse(
            id=c.id,
            post_id=c.post_id,
            parent_id=c.parent_id,
            content=c.content,
            is_anonymous=c.is_anonymous,
            nickname_type=getattr(c, "nickname_type", "anon"),
            like_count=c.like_count,
            is_hidden=c.is_hidden,
            is_post_author=(c.author_id == post_author_id),
            is_liked=(c.id in liked_ids),
            is_mine=(c.author_id == user.id),
            anon_label=anon_labels.get(c.author_id) if c.is_anonymous else None,
            author_nickname=_comment_display_name(c),
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
        await temperature_service.adjust(comment.author_id, "comment_unliked", db)
    else:
        db.add(Like(user_id=user.id, target_type="comment", target_id=comment_id))
        comment.like_count += 1
        liked = True
        await temperature_service.adjust(comment.author_id, "comment_liked", db)

    await db.commit()
    return {"like_count": comment.like_count, "is_liked": liked}
