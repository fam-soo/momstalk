from datetime import datetime, timedelta, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_, and_
from sqlalchemy.exc import IntegrityError

from app.core.profanity import check_profanity
from app.models.service_models import Block, Comment, Like, Post, Report, Scrap, School, User
from app.schemas.post import PostCreate, PostListItem, PostResponse, ScrapResponse, PostUpdate
from app.services import temperature_service
from app.services.school_unlock_service import get_unlock_status

# 지역/학원 게시판은 자유롭게 열되, 학교 게시판(school/grade)만 같은 학교
# 정회원이 일정 인원 모여야 잠금 해제된다 (school_unlock_service 참고).
SCHOOL_GATED_BOARDS = {"school", "grade"}

REPORT_AUTO_HIDE_THRESHOLD = 5

# 익명 작성 옵션을 선택할 수 있는 게시판. grade(학년/반)·notice(공지)는 실명(닉네임) 고정.
ANON_ALLOWED_BOARDS = {"school", "free", "region"}


def _resolve_nickname_snapshot(nickname_type: str, is_anonymous: bool, author: User) -> str | None:
    """작성 시점에 고정해서 저장할 닉네임 계산 (익명이면 저장 안 함)."""
    if nickname_type == "certified":
        return author.certified_nickname or author.nickname
    if not is_anonymous:
        return author.nickname
    return None


def _author_display_name(post_or_comment, author: User) -> str | None:
    """표시용 닉네임 반환. 관리자 작성 글은 항상 '관리자' 표시.

    작성 시점에 저장해둔 nickname_snapshot을 우선 사용해 이후 유저가 닉네임을
    바꿔도 과거 글의 표시명은 그대로 유지되게 한다. 스냅샷이 없는 과거 데이터
    (마이그레이션 이전에 작성된 행 중 백필이 안 된 경우)만 현재 닉네임으로 대체한다.
    """
    if author.is_admin:
        return "관리자"
    snapshot = getattr(post_or_comment, "nickname_snapshot", None)
    if snapshot:
        return snapshot
    nickname_type = getattr(post_or_comment, "nickname_type", "anon")
    if nickname_type == "certified":
        return author.certified_nickname or author.nickname
    if not getattr(post_or_comment, "is_anonymous", True):
        return author.nickname
    return None


async def create_post(user: User, req: PostCreate, db: AsyncSession) -> Post:
    if req.board_type == "notice" and not user.is_admin:
        raise ValueError("공지사항은 관리자만 작성할 수 있습니다.")
    if req.board_type in ("school", "grade", "free", "region") and user.member_grade != "member" and not user.is_admin:
        raise ValueError("학부모 인증 정회원만 게시글을 작성할 수 있습니다.")
    if req.board_type not in ANON_ALLOWED_BOARDS:
        req.is_anonymous = False
        req.nickname_type = "anon"
    check_profanity(req.title, "제목")
    check_profanity(req.content, "내용")
    active = user.active_child
    school_code = (active.school_code if active else None) or user.school_code
    grade = (active.grade if active else None) or user.grade
    class_num = (active.class_num if active else None) or user.class_num
    target_region = None

    if req.board_type == "notice":
        # 공지사항 타겟 범위: 학교 지정 > 지역 지정 > 전체(둘 다 미지정)
        if req.target_school_code:
            school_code = req.target_school_code
        elif req.target_region:
            school_code = None
            target_region = req.target_region
        else:
            school_code = None  # 전체 공지 — 모든 게시판 상단에 노출
    elif user.is_admin and req.target_school_code:
        school_code = req.target_school_code
    elif user.is_admin and req.target_region and req.board_type == "region":
        row = (await db.execute(
            select(School.school_code).where(School.region == req.target_region).limit(1)
        )).scalar_one_or_none()
        if row:
            school_code = row

    if req.board_type in SCHOOL_GATED_BOARDS and not user.is_admin:
        unlock = await get_unlock_status(school_code, db)
        if not unlock["unlocked"]:
            raise ValueError("학교 게시판이 아직 잠겨 있어요. 같은 학교 학부모가 더 모이면 열려요.")

    if req.board_type == "grade" and not grade and not user.is_admin:
        raise ValueError("학년 정보가 없어 학년 게시판을 이용할 수 없어요. 내정보에서 학년을 선택해주세요.")

    post = Post(
        author_id=user.id,
        board_type=req.board_type,
        school_code=school_code,
        target_region=target_region,
        grade=grade if req.board_type in ("class", "grade") else None,
        class_num=class_num if req.board_type == "class" else None,
        title=req.title,
        content=req.content,
        is_anonymous=req.is_anonymous,
        nickname_type=req.nickname_type,
        nickname_snapshot=_resolve_nickname_snapshot(req.nickname_type, req.is_anonymous, user),
        mention_tags=req.mention_tags or None,
    )
    db.add(post)
    await temperature_service.adjust(user.id, "post_created", db)
    await db.commit()
    await db.refresh(post)

    if post.board_type in ("region", "school", "grade"):
        from app.services.notification_service import notify_new_post
        await notify_new_post(db, post)

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
        select(func.count()).where(Comment.post_id == post.id, Comment.is_hidden == False, Comment.is_deleted == False)
    )).scalar() or 0
    author = (await db.execute(select(User).where(User.id == post.author_id))).scalar_one_or_none()
    display_name = _author_display_name(post, author) if author else None
    return PostResponse(
        id=post.id,
        board_type=post.board_type,
        title=post.title,
        content=post.content,
        is_anonymous=post.is_anonymous,
        nickname_type=getattr(post, "nickname_type", "anon"),
        author_display_name=display_name,
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
    size: int,
    user: User,
    db: AsyncSession,
    q: str | None = None,
    sort: str = "recent",       # "recent" | "popular"
    cursor: int | None = None,  # cursor 기반 페이지네이션: 마지막 post.id
) -> "PostListResponse":
    from app.schemas.post import PostListResponse

    if board_type in SCHOOL_GATED_BOARDS and not user.is_admin:
        unlock = await get_unlock_status(school_code, db)
        if not unlock["unlocked"]:
            raise ValueError("학교 게시판이 아직 잠겨 있어요. 같은 학교 학부모가 더 모이면 열려요.")

    if board_type == "grade" and not grade and not user.is_admin:
        raise ValueError("학년 정보가 없어 학년 게시판을 이용할 수 없어요. 내정보에서 학년을 선택해주세요.")

    # 차단한 유저의 게시글 제외
    blocked_ids_result = await db.execute(select(Block.blocked_user_id).where(Block.user_id == user.id))
    blocked_ids = {r for r in blocked_ids_result.scalars()}

    query = select(Post).where(Post.board_type == board_type, Post.is_hidden == False, Post.is_deleted == False)

    if blocked_ids:
        query = query.where(Post.author_id.notin_(blocked_ids))

    if q:
        query = query.where(or_(Post.title.ilike(f"%{q}%"), Post.content.ilike(f"%{q}%")))

    _DEFAULT_REGION = "양천구"
    effective_region = user.region or _DEFAULT_REGION

    # 관리자: 모든 지역/학교 필터 없이 전체 조회
    if not user.is_admin:
        if board_type == "region":
            # 일반 유저 글: 같은 지역 유저의 school_code 기준
            # 관리자 공지: School 테이블의 region 기준 (등록된 유저 없어도 표시)
            query = query.where(
                or_(
                    Post.school_code.in_(
                        select(User.school_code).where(User.region == effective_region)
                    ),
                    Post.school_code.in_(
                        select(School.school_code).where(School.region == effective_region)
                    ),
                )
            )
        elif board_type == "free":
            pass
        else:
            query = query.where(Post.school_code == school_code)
            if board_type == "grade" and grade:
                query = query.where(Post.grade == grade)

    # cursor 필터 + 정렬
    if sort == "popular":
        # 인기순: like_count DESC → id DESC (cursor는 id 기준)
        if cursor is not None:
            # cursor 이후의 행: 같은 like_count에서 id < cursor, 또는 like_count 더 낮은 행
            cursor_post = (await db.execute(select(Post).where(Post.id == cursor))).scalar_one_or_none()
            if cursor_post:
                query = query.where(
                    or_(
                        Post.like_count < cursor_post.like_count,
                        (Post.like_count == cursor_post.like_count) & (Post.id < cursor),
                    )
                )
        query = query.order_by(Post.like_count.desc(), Post.id.desc()).limit(size + 1)
    else:
        # 최신순: id DESC cursor
        if cursor is not None:
            query = query.where(Post.id < cursor)
        query = query.order_by(Post.id.desc()).limit(size + 1)

    posts = list((await db.execute(query)).scalars().all())

    # 다음 페이지 존재 여부
    has_more = len(posts) > size
    if has_more:
        posts = posts[:size]
    next_cursor = posts[-1].id if has_more and posts else None

    # 공지사항: 이 게시판 범위(학교/지역/전체)에 해당하는 공지를 최상단에 고정.
    # 페이지네이션과 무관하게 항상 붙어야 하므로 첫 페이지(cursor 없음)에만 붙인다.
    notice_ids: set[int] = set()
    if cursor is None and board_type != "notice":
        notice_query = select(Post).where(
            Post.board_type == "notice", Post.is_hidden == False, Post.is_deleted == False
        )
        _global_notice = and_(Post.school_code.is_(None), Post.target_region.is_(None))
        if board_type == "region":
            notice_query = notice_query.where(or_(Post.target_region == effective_region, _global_notice))
        elif board_type in ("school", "grade"):
            notice_query = notice_query.where(or_(Post.school_code == school_code, _global_notice))
        else:  # free
            notice_query = notice_query.where(_global_notice)
        notice_query = notice_query.order_by(Post.created_at.desc()).limit(3)
        notices = list((await db.execute(notice_query)).scalars().all())
        if notices:
            notice_ids = {p.id for p in notices}
            posts = notices + [p for p in posts if p.id not in notice_ids]

    # 유저 @태그 집합
    user_tags: set[str] = set()
    if user.region:
        user_tags.add(user.region)
    if user.school_name:
        user_tags.add(user.school_name)
    if user.grade:
        user_tags.add(f"{user.grade}학년")

    def _is_pinned(p: Post) -> bool:
        if p.id in notice_ids:
            return False
        return bool(user_tags & set(p.mention_tags or []))

    def _hot_score(p: Post, comment_count: int) -> float:
        now = datetime.now(timezone.utc)
        age_hours = (now - p.created_at.replace(tzinfo=timezone.utc)).total_seconds() / 3600
        if age_hours > 7 * 24:
            return 0.0
        decay = 1.0 if age_hours <= 24 else (0.7 if age_hours <= 72 else 0.4)
        return (p.like_count * 2 + comment_count * 1.5 + p.scrap_count - p.report_count * 3) * decay

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

    comment_counts: dict[int, int] = {}
    hot_scores: dict[int, float] = {}
    for post in posts:
        cnt = (await db.execute(
            select(func.count()).where(Comment.post_id == post.id, Comment.is_hidden == False, Comment.is_deleted == False)
        )).scalar() or 0
        comment_counts[post.id] = cnt
        if post.id in notice_ids:
            continue  # 공지는 인기글 산정에서 제외
        score = _hot_score(post, cnt)
        if score >= 3:
            hot_scores[post.id] = score

    # 인기글은 최대 3개로 제한 (게시판 전체 글이 적을 때 과도하게 붙는 것 방지)
    top_hot_ids = set(sorted(hot_scores, key=lambda pid: hot_scores[pid], reverse=True)[:3])

    # 공지는 정렬 기준과 무관하게 항상 최상단, 그다음 인기글/고정글(최신순일 때만), 나머지는 기존 정렬 유지
    def _sort_key(p: Post):
        if p.id in notice_ids:
            return (0, -p.created_at.timestamp())
        if sort == "recent":
            if p.id in top_hot_ids:
                return (1, -p.created_at.timestamp())
            if _is_pinned(p):
                return (2, -p.created_at.timestamp())
            return (3, -p.created_at.timestamp())
        return (1, 0)  # 인기순 등 기존 정렬 유지 (안정 정렬이므로 원래 순서 보존)
    posts = sorted(posts, key=_sort_key)

    author_ids = {p.author_id for p in posts}
    authors_result = await db.execute(select(User).where(User.id.in_(author_ids)))
    authors: dict[int, User] = {u.id: u for u in authors_result.scalars()}

    items = []
    for post in posts:
        tags = post.mention_tags or []
        author = authors.get(post.author_id)
        display_name = _author_display_name(post, author) if author else None
        items.append(PostListItem(
            id=post.id,
            board_type=post.board_type,
            title=post.title,
            is_anonymous=post.is_anonymous,
            nickname_type=getattr(post, "nickname_type", "anon"),
            author_display_name=display_name,
            author_region=author.region if author else None,
            author_school=author.school_name if author else None,
            view_count=post.view_count,
            like_count=post.like_count,
            scrap_count=post.scrap_count,
            comment_count=comment_counts[post.id],
            mention_tags=tags,
            is_liked=post.id in liked_ids,
            is_pinned=_is_pinned(post),
            is_notice=post.id in notice_ids,
            is_hot=post.id in top_hot_ids,
            created_at=post.created_at,
        ))
    return PostListResponse(items=items, next_cursor=next_cursor)


async def get_hot_posts(user: User, db: AsyncSession, limit: int = 30) -> "PostListResponse":
    """지역·학교·학원 게시판을 가로질러 인기글만 모아 보여주는 '인기' 탭용.

    초기 활성화 단계에서 학교 게시판은 잠겨 있고 개별 게시판 콘텐츠도 아직
    적어, 신규 유저가 "볼 게 없어서" 이탈하는 문제를 완화하기 위한 화면.
    list_posts()의 _hot_score와 동일한 기준(좋아요*2 + 댓글*1.5 + 스크랩 -
    신고*3, 7일 이내 최신도 감쇠)을 사용하되 여러 게시판을 한 번에 훑는다.
    """
    from app.schemas.post import PostListResponse

    blocked_ids_result = await db.execute(select(Block.blocked_user_id).where(Block.user_id == user.id))
    blocked_ids = {r for r in blocked_ids_result.scalars()}

    _DEFAULT_REGION = "양천구"
    effective_region = user.region or _DEFAULT_REGION
    since = datetime.utcnow() - timedelta(days=7)

    query = select(Post).where(
        Post.board_type.in_(("region", "free", "school", "grade")),
        Post.is_hidden == False,
        Post.is_deleted == False,
        Post.created_at >= since,
    )
    if blocked_ids:
        query = query.where(Post.author_id.notin_(blocked_ids))

    if not user.is_admin:
        active = user.active_child
        school_code = (active.school_code if active else None) or user.school_code
        school_unlocked = False
        if school_code:
            unlock = await get_unlock_status(school_code, db)
            school_unlocked = unlock["unlocked"]

        _region_match = or_(
            Post.school_code.in_(select(User.school_code).where(User.region == effective_region)),
            Post.school_code.in_(select(School.school_code).where(School.region == effective_region)),
        )
        scope_conditions = [
            Post.board_type == "free",
            and_(Post.board_type == "region", _region_match),
        ]
        if school_unlocked and school_code:
            scope_conditions.append(and_(Post.board_type.in_(("school", "grade")), Post.school_code == school_code))
        query = query.where(or_(*scope_conditions))

    query = query.order_by(Post.created_at.desc()).limit(300)  # 산정 후보 풀
    posts = list((await db.execute(query)).scalars().all())

    def _hot_score(p: Post, comment_count: int) -> float:
        now = datetime.now(timezone.utc)
        age_hours = (now - p.created_at.replace(tzinfo=timezone.utc)).total_seconds() / 3600
        decay = 1.0 if age_hours <= 24 else (0.7 if age_hours <= 72 else 0.4)
        return (p.like_count * 2 + comment_count * 1.5 + p.scrap_count - p.report_count * 3) * decay

    comment_counts: dict[int, int] = {}
    for post in posts:
        comment_counts[post.id] = (await db.execute(
            select(func.count()).where(Comment.post_id == post.id, Comment.is_hidden == False, Comment.is_deleted == False)
        )).scalar() or 0

    scored = sorted(
        posts,
        key=lambda p: (_hot_score(p, comment_counts[p.id]), p.created_at),
        reverse=True,
    )[:limit]

    post_ids = [p.id for p in scored]
    liked_ids: set[int] = set()
    if post_ids:
        likes_result = await db.execute(
            select(Like.target_id).where(
                Like.user_id == user.id, Like.target_type == "post", Like.target_id.in_(post_ids),
            )
        )
        liked_ids = {row for row in likes_result.scalars()}

    author_ids = {p.author_id for p in scored}
    authors_result = await db.execute(select(User).where(User.id.in_(author_ids)))
    authors: dict[int, User] = {u.id: u for u in authors_result.scalars()}

    items = []
    for post in scored:
        author = authors.get(post.author_id)
        display_name = _author_display_name(post, author) if author else None
        items.append(PostListItem(
            id=post.id,
            board_type=post.board_type,
            title=post.title,
            is_anonymous=post.is_anonymous,
            nickname_type=getattr(post, "nickname_type", "anon"),
            author_display_name=display_name,
            author_region=author.region if author else None,
            author_school=author.school_name if author else None,
            view_count=post.view_count,
            like_count=post.like_count,
            scrap_count=post.scrap_count,
            comment_count=comment_counts[post.id],
            mention_tags=post.mention_tags or [],
            is_liked=post.id in liked_ids,
            is_pinned=False,
            is_notice=False,
            is_hot=True,
            created_at=post.created_at,
        ))
    return PostListResponse(items=items, next_cursor=None)


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
        await temperature_service.adjust(post.author_id, "post_unliked", db)
    else:
        db.add(Like(user_id=user.id, target_type="post", target_id=post_id))
        post.like_count += 1
        liked = True
        await temperature_service.adjust(post.author_id, "post_liked", db)

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
            await temperature_service.adjust(target.author_id, "post_hidden", db)

    await db.commit()
