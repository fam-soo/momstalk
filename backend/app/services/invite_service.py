"""
추천 링크 서비스.

- 정회원(member)이 발급 → 발급자의 school_code 고정
- 48시간 유효, 1회 사용
- 사용 시 신규 유저의 member_grade = 'member' 로 즉시 승급
"""
import secrets
from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.service_models import InviteLink, User


async def generate_invite(issuer: User, db: AsyncSession, child_id: int | None = None) -> InviteLink:
    """정회원만 호출 가능. active_child(또는 지정 child)의 school 고정, 48시간 유효."""
    # 다자녀 지원: active_child 우선, 없으면 deprecated 필드 fallback
    source = None
    if child_id:
        from app.models.service_models import UserChild
        from sqlalchemy import select as sa_select
        result = await db.execute(sa_select(UserChild).where(UserChild.id == child_id, UserChild.user_id == issuer.id))
        source = result.scalar_one_or_none()
    if not source:
        source = issuer.active_child

    school_code = (source.school_code if source else issuer.school_code) or ""
    school_name = (source.school_name if source else issuer.school_name) or ""
    school_type = (source.school_type if source else issuer.school_type) or "elementary"

    if not school_code:
        raise ValueError("학교 정보가 없습니다. 자녀 정보를 먼저 등록해주세요.")

    token = secrets.token_urlsafe(32)
    link = InviteLink(
        token=token,
        issuer_id=issuer.id,
        school_code=school_code,
        school_name=school_name,
        school_type=school_type,
        expires_at=datetime.utcnow() + timedelta(hours=48),
    )
    db.add(link)
    await db.commit()
    await db.refresh(link)
    return link


async def get_invite(token: str, db: AsyncSession) -> InviteLink | None:
    result = await db.execute(select(InviteLink).where(InviteLink.token == token))
    return result.scalar_one_or_none()


async def validate_invite(token: str, db: AsyncSession) -> InviteLink:
    """유효성 검증. 실패 시 ValueError."""
    link = await get_invite(token, db)
    if not link:
        raise ValueError("유효하지 않은 초대 링크입니다.")
    if link.used_by is not None:
        raise ValueError("이미 사용된 초대 링크입니다.")
    if datetime.utcnow() > link.expires_at:
        raise ValueError("만료된 초대 링크입니다.")
    return link


async def use_invite(token: str, user: User, grade: int, class_num: int | None, db: AsyncSession) -> None:
    """링크 사용 → user_children에 자녀 추가 + 비정회원이면 즉시 정회원 승급."""
    from app.models.service_models import UserChild
    from sqlalchemy import select as sa_select

    link = await validate_invite(token, db)
    link.used_by = user.id
    link.used_at = datetime.utcnow()

    # 같은 school_code의 자녀가 이미 있으면 학년만 업데이트, 없으면 추가
    result = await db.execute(
        sa_select(UserChild).where(
            UserChild.user_id == user.id,
            UserChild.school_code == link.school_code,
        )
    )
    existing_child = result.scalar_one_or_none()

    if existing_child:
        existing_child.grade = grade
        if class_num is not None:
            existing_child.class_num = class_num
        child = existing_child
    else:
        child = UserChild(
            user_id=user.id,
            school_code=link.school_code,
            school_name=link.school_name,
            school_type=link.school_type,
            grade=grade,
            class_num=class_num,
            region=user.region,
        )
        db.add(child)
        await db.flush()

    # active_child가 없으면 방금 추가한 자녀를 활성으로 설정
    if not user.active_child_id:
        user.active_child_id = child.id

    # deprecated 필드도 동기화 (기존 코드 호환)
    user.school_code = link.school_code
    user.school_name = link.school_name
    user.school_type = link.school_type
    user.grade = grade
    if class_num is not None:
        user.class_num = class_num

    # 비정회원이면 정회원 승급
    if user.member_grade != "member":
        user.member_grade = "member"
        user.auth_route = "invite"
        user.auth_pending = False

    await db.commit()
