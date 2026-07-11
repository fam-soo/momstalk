"""
추천 링크 서비스.

- 정회원(member)이 발급 → 발급자의 school_code 고정
- 24시간 유효, 최대 max_uses(기본 10)명까지 함께 사용 가능(1회 소모성 아님)
  — 카카오톡 단체 채팅방 등으로 한 링크를 여러 명에게 동시에 공유하는
  경우가 많아 정원제로 운영한다.
- 사용 시 신규 유저의 member_grade = 'member' 로 즉시 승급
"""
import secrets
from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.service_models import InviteLink, InviteLinkUse, User

INVITE_EXPIRES_HOURS = 24
INVITE_MAX_USES = 10


async def generate_invite(issuer: User, db: AsyncSession, child_id: int | None = None) -> InviteLink:
    """정회원만 호출 가능. active_child(또는 지정 child)의 school 고정, 24시간·최대 10명."""
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
        max_uses=INVITE_MAX_USES,
        expires_at=datetime.utcnow() + timedelta(hours=INVITE_EXPIRES_HOURS),
    )
    db.add(link)
    await db.commit()
    await db.refresh(link)
    return link


async def get_invite(token: str, db: AsyncSession) -> InviteLink | None:
    result = await db.execute(select(InviteLink).where(InviteLink.token == token))
    return result.scalar_one_or_none()


async def validate_invite(token: str, db: AsyncSession, user: "User | None" = None) -> InviteLink:
    """존재·만료 여부만 확인(정원 확인은 use_invite에서 원자적으로 처리).
    실패 시 ValueError."""
    link = await get_invite(token, db)
    if not link:
        raise ValueError("유효하지 않은 초대 링크입니다.")
    if datetime.utcnow() > link.expires_at:
        raise ValueError("만료된 초대 링크입니다.")
    return link


async def use_invite(token: str, user: User, grade: int, class_num: int | None, db: AsyncSession) -> dict:
    """링크 사용 → user_children에 자녀 추가 + 비정회원이면 즉시 정회원 승급.
    기존 정회원이 사용하는 경우 자녀만 추가하고 정원을 소비하지 않음."""
    from app.models.service_models import UserChild
    from sqlalchemy import select as sa_select

    was_member = user.member_grade == "member"
    link = await validate_invite(token, db, user=user)

    # 기존 정회원이 아닌 경우에만 정원을 소비한다(신규/lurker 가입용).
    if not was_member:
        already_used = (await db.execute(
            sa_select(InviteLinkUse).where(
                InviteLinkUse.invite_link_id == link.id, InviteLinkUse.user_id == user.id,
            )
        )).scalar_one_or_none()
        if not already_used:
            # "정원 확인" → "자리 선점"이 별개 요청이면 그 사이 다른 사람이 먼저
            # 채워 정원을 넘길 수 있다(같은 링크를 여러 명이 동시에 열 때 흔함).
            # WHERE use_count < max_uses 조건의 원자적 UPDATE로 선점하고,
            # 실패(rowcount=0)한 요청만 "정원 초과"로 처리한다.
            result = await db.execute(
                InviteLink.__table__.update()
                .where(InviteLink.id == link.id, InviteLink.use_count < InviteLink.max_uses)
                .values(use_count=InviteLink.use_count + 1, used_by=user.id, used_at=datetime.utcnow())
            )
            if result.rowcount == 0:
                raise ValueError("이 초대 링크는 참여 인원이 가득 찼습니다. 발급자에게 새 링크를 요청해주세요.")
            db.add(InviteLinkUse(invite_link_id=link.id, user_id=user.id))

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
    return {"was_member": was_member}
