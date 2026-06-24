from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_
from sqlalchemy.exc import IntegrityError

from app.core.profanity import check_profanity
from app.models.service_models import Block, Comment, Like, Post, Report, Scrap, User
from app.schemas.post import PostCreate, PostListItem, PostResponse, ScrapResponse, PostUpdate

REPORT_AUTO_HIDE_THRESHOLD = 5


async def create_post(user: User, req: PostCreate, db: AsyncSession) -> Post:
    check_profanity(req.title, "제목")
    check_profanity(req.content, "내용")
    post = Post(
        author_id=user.id,
        board_type=req.board_type,
        school_code=user.school_code,
        grade=user.grade if req.board_type in ("class", "grade") else None,
        class_num=user.class_num if req.board_type == "class" else None,
        title=req.title,
        content=req.content,
        is_anonymous=req.is_anonymous,
        mention_tags=req.mention_tags or None,
    )
    db.add(post)
    await db.commit()
    await db.refresh(post)
    return post


async def get_post(post_id: int, db: AsyncSession) -> Post | None:
    result = await db.execute(select(Post).where(Post.id == post_id))
    post = result.scalar_one_or_none()
    if post:
        post.view_count += 1
        await db.commit()
    return post


async def get_post_response(post: Post, user: User, db: AsyncSession) -> PostResponse:
    """Post 모델 → is_liked / is_scraped 플래그 포함 응답 DTO 변환."""
    like = await db.execute(
        select(Like).where(Like.user_id == user.id, Like.target_type == "post", Like.target_id == post.id)
    )
    scrap = await db.execute(
        select(Scrap).where(Scrap.user_id == user.id, Scrap.post_id == post.id)
    )
    comment_count = (await db.execute(
        select(func.count()).where(Comment.post_id == post.id, Comment.is_hidden == False)
    )).scalar() or 0
    return PostResponse(
        id=post.id,
        board_type=post.board_type,
        title=post.title,
        content=post.content,
        is_anonymous=post.is_anonymous,
        view_count=post.view_count,
        like_count=post.like_count,
        scrap_count=post.scrap_count,
        report_count=post.report_count,
        is_hidden=post.is_hidden,
        comment_count=comment_count,
        mention_tags=post.mention_tags or [],
        created_at=post.created_at,
        updated_at=post.updated_at,
        is_liked=like.scalar_one_or_none() is not None,
        is_scraped=scrap.scalar_one_or_none() is not None,
        is_mine=post.author_id == user.id,
    )


async def list_posts(
    board_type: str,
    school_code: str,
    grade: int | None,
    class_num: int | None,
    page: int,
    size: int,
    user: User,
    db: AsyncSession,
    q: str | None = None,
) -> list[PostListItem]:
    # 차단한 유저의 게시글 제외
    blocked_ids_result = await db.execute(select(Block.blocked_user_id).where(Block.user_id == user.id))
    blocked_ids = {r for r in blocked_ids_result.scalars()}

    query = select(Post).where(Post.board_type == board_type, Post.is_hidden == False, Post.is_deleted == False)

    if blocked_ids:
        query = query.where(Post.author_id.notin_(blocked_ids))

    # 검색어 필터
    if q:
        query = query.where(or_(Post.title.ilike(f"%{q}%"), Post.content.ilike(f"%{q}%")))

    if board_type == "region":
        # 지역 게시판: 같은 지역(user.region) 기준
        query = query.where(Post.school_code.in_(
            select(User.school_code).where(User.region == user.region)
        ))
    elif board_type == "free":
        # 전체 게시판: 학교 필터 없음, @태그 매칭 게시글을 상단 노출
        pass  # 필터 없음 — 아래에서 정렬만
    else:
        # 학교/학년: 같은 학교 기준
        query = query.where(Post.school_code == school_code)
        if board_type == "grade" and grade:
            query = query.where(Post.grade == grade)

    query = query.order_by(Post.created_at.desc()).offset((page - 1) * size).limit(size)
    posts = list((await db.execute(query)).scalars().all())

    # 유저 프로필 기반 @태그 매칭용 집합 (모든 게시판 공통)
    user_tags: set[str] = set()
    if user.region:
        user_tags.add(user.region)
    if user.school_name:
        user_tags.add(user.school_name)
    if user.grade:
        user_tags.add(f"{user.grade}학년")

    def _is_pinned(p: Post) -> bool:
        return bool(user_tags & set(p.mention_tags or []))

    def _hot_score(p: Post, comment_count: int) -> float:
        now = datetime.now(timezone.utc)
        age_hours = (now - p.created_at.replace(tzinfo=timezone.utc)).total_seconds() / 3600
        if age_hours > 7 * 24:
            return 0.0
        decay = 1.0 if age_hours <= 24 else (0.7 if age_hours <= 72 else 0.4)
        return (p.like_count * 2 + comment_count * 1.5 + p.scrap_count - p.report_count * 3) * decay

    # 현재 유저의 좋아요 여부 일괄 조회
    post_ids = [p.id for p in posts]
    liked_ids: set[int] = set()
    if post_ids:
        likes_result = await db.execute(
            select(Like.target_id).where(
                Like.user_id == user.id,
                Like.target_type == "post",
                Like.target_id.in_(post_ids),
            )
        )
        liked_ids = {row for row in likes_result.scalars()}

    # 댓글 수 일괄 계산 + 인기글 후보 판별
    comment_counts: dict[int, int] = {}
    hot_scores: dict[int, float] = {}
    for post in posts:
        cnt = (await db.execute(
            select(func.count()).where(Comment.post_id == post.id, Comment.is_hidden == False)
        )).scalar() or 0
        comment_counts[post.id] = cnt
        score = _hot_score(post, cnt)
        if score >= 3:
            hot_scores[post.id] = score

    # 인기글: 최대 3개, 점수 높은 순
    top_hot_ids = set(sorted(hot_scores, key=lambda pid: hot_scores[pid], reverse=True)[:3])

    # @태그 매칭 게시글 상단 + 인기글 최상단 정렬
    # 정렬 키: (hot=0 > pinned=1 > normal=2, 최신순)
    def _sort_key(p: Post):
        if p.id in top_hot_ids:
            return (0, -p.created_at.timestamp())
        if _is_pinned(p):
            return (1, -p.created_at.timestamp())
        return (2, -p.created_at.timestamp())

    posts = sorted(posts, key=_sort_key)

    items = []
    for post in posts:
        tags = post.mention_tags or []
        items.append(PostListItem(
            id=post.id,
            board_type=post.board_type,
            title=post.title,
            is_anonymous=post.is_anonymous,
            view_count=post.view_count,
            like_count=post.like_count,
            scrap_count=post.scrap_count,
            comment_count=comment_counts[post.id],
            mention_tags=tags,
            is_liked=post.id in liked_ids,
            is_pinned=_is_pinned(post),
            is_hot=post.id in top_hot_ids,
            created_at=post.created_at,
        ))
    return items


async def update_post(post: Post, req: PostUpdate, db: AsyncSession) -> Post:
    if req.title is not None:
        check_profanity(req.title, "제목")
        post.title = req.title
    if req.content is not None:
        check_profanity(req.content, "내용")
        post.content = req.content
    await db.commit()
    await db.refresh(post)
    return post


async def delete_post(post: Post, db: AsyncSession) -> None:
    post.is_deleted = True
    await db.commit()


async def toggle_like_post(post_id: int, user: User, db: AsyncSession) -> dict:
    """좋아요 토글. DB 레벨 UNIQUE 제약으로 중복 방지."""
    result = await db.execute(select(Post).where(Post.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise ValueError("게시글을 찾을 수 없습니다.")

    existing = await db.execute(
        select(Like).where(Like.user_id == user.id, Like.target_type == "post", Like.target_id == post_id)
    )
    like = existing.scalar_one_or_none()

    if like:
        await db.delete(like)
        post.like_count = max(0, post.like_count - 1)
        liked = False
    else:
        db.add(Like(user_id=user.id, target_type="post", target_id=post_id))
        post.like_count += 1
        liked = True

    await db.commit()
    return {"like_count": post.like_count, "is_liked": liked}


async def toggle_scrap(post_id: int, user: User, db: AsyncSession) -> dict:
    """스크랩 토글. DB 레벨 UNIQUE 제약으로 중복 방지."""
    result = await db.execute(select(Post).where(Post.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise ValueError("게시글을 찾을 수 없습니다.")

    existing = await db.execute(
        select(Scrap).where(Scrap.user_id == user.id, Scrap.post_id == post_id)
    )
    scrap = existing.scalar_one_or_none()

    if scrap:
        await db.delete(scrap)
        post.scrap_count = max(0, post.scrap_count - 1)
        scraped = False
    else:
        db.add(Scrap(user_id=user.id, post_id=post_id))
        post.scrap_count += 1
        scraped = True

    await db.commit()
    return {"scrap_count": post.scrap_count, "is_scraped": scraped}


async def list_scraps(user: User, db: AsyncSession) -> list[ScrapResponse]:
    result = await db.execute(
        select(Post)
        .join(Scrap, Scrap.post_id == Post.id)
        .where(Scrap.user_id == user.id, Post.is_hidden == False, Post.is_deleted == False)
        .order_by(Scrap.created_at.desc())
    )
    posts = result.scalars().all()
    return [
        ScrapResponse(
            id=p.id,
            title=p.title,
            board_type=p.board_type,
            like_count=p.like_count,
            scrap_count=p.scrap_count,
            created_at=p.created_at,
        )
        for p in posts
    ]


async def report_content(
    reporter: User,
    target_type: str,
    target_id: int,
    category: str,
    reason: str,
    db: AsyncSession,
) -> None:
    try:
        db.add(Report(
            reporter_id=reporter.id,
            target_type=target_type,
            target_id=target_id,
            category=category,
            reason=reason,
        ))
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise ValueError("이미 신고한 게시물입니다.")

    if target_type == "post":
        result = await db.execute(select(Post).where(Post.id == target_id))
        target = result.scalar_one_or_none()
    else:
        result = await db.execute(select(Comment).where(Comment.id == target_id))
        target = result.scalar_one_or_none()

    if target:
        target.report_count += 1
        if target.report_count >= REPORT_AUTO_HIDE_THRESHOLD:
            target.is_hidden = True

    await db.commit()
