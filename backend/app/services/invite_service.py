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


async def validate_invite(token: str, db: AsyncSession, user: "User | None" = None) -> InviteLink:
    """유효성 검증. 실패 시 ValueError.
    기존 정회원(user.member_grade == 'member')이 이미 사용된 링크를 쓸 때는 허용."""
    link = await get_invite(token, db)
    if not link:
        raise ValueError("유효하지 않은 초대 링크입니다.")
    if link.used_by is not None:
        # 기존 정회원이 자녀 추가 목적으로 사용하는 경우 허용
        if user is None or user.member_grade != "member":
            raise ValueError("이미 사용된 초대 링크입니다.")
    if datetime.utcnow() > link.expires_at:
        raise ValueError("만료된 초대 링크입니다.")
    return link


async def use_invite(token: str, user: User, grade: int, class_num: int | None, db: AsyncSession) -> dict:
    """링크 사용 → user_children에 자녀 추가 + 비정회원이면 즉시 정회원 승급.
    기존 정회원이 사용하는 경우 자녀만 추가하고 링크는 소모하지 않음."""
    from app.models.service_models import UserChild
    from sqlalchemy import select as sa_select

    was_member = user.member_grade == "member"
    link = await validate_invite(token, db, user=user)

    # 기존 정회원이 아닌 경우에만 링크 소모 (신규/lurker 가입용).
    # validate_invite에서 used_by를 확인한 시점과 여기서 실제로 값을 쓰는
    # 시점 사이에 간격이 있어, 같은 링크를 두 사람이 거의 동시에(예: 한 링크를
    # 전달받은 두 학부모가 동시에 가입 버튼을 누름) 열면 둘 다 "아직 미사용"
    # 상태를 보고 통과해 링크 하나로 두 명이 정회원이 될 수 있었다.
    # WHERE used_by IS NULL 조건의 원자적 UPDATE로 선점해, 늦게 도착한 요청은
    # rowcount=0으로 감지해 실패 처리한다.
    if not was_member:
        result = await db.execute(
            InviteLink.__table__.update()
            .where(InviteLink.token == token, InviteLink.used_by.is_(None))
            .values(used_by=user.id, used_at=datetime.utcnow())
        )
        if result.rowcount == 0:
            raise ValueError("이미 사용된 초대 링크입니다.")

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
