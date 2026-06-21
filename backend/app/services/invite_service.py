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


async def generate_invite(issuer: User, db: AsyncSession) -> InviteLink:
    """정회원만 호출 가능. 같은 school_code 고정, 48시간 유효."""
    token = secrets.token_urlsafe(32)
    link = InviteLink(
        token=token,
        issuer_id=issuer.id,
        school_code=issuer.school_code,
        school_name=issuer.school_name,
        school_type=issuer.school_type,
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
    """링크 사용 → user.member_grade = 'member', school 정보 채움."""
    link = await validate_invite(token, db)
    if user.member_grade == "member":
        raise ValueError("이미 정회원입니다.")

    link.used_by = user.id
    link.used_at = datetime.utcnow()

    user.member_grade = "member"
    user.auth_route = "invite"
    user.auth_pending = False
    user.school_code = link.school_code
    user.school_name = link.school_name
    user.school_type = link.school_type
    user.grade = grade
    if class_num is not None:
        user.class_num = class_num

    await db.commit()
