"""
학부모 인증 서비스.
SMS 토큰(전화번호 증명) → anon_id 생성 → 인증 DB 저장 → 서비스 DB User 생성/조회 → JWT 발급.
인증 DB와 서비스 DB 사이에는 anon_id라는 단방향 해시값만 공유되며,
역추적은 수학적으로 불가능하다.
"""
import random
import string

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.security import make_anon_id, create_access_token, create_refresh_token
from app.models.auth_models import ParentVerification
from app.models.service_models import User
from app.schemas.auth import ParentVerifyRequest


def _random_nickname() -> str:
    adjectives = ["용감한", "따뜻한", "지혜로운", "밝은", "든든한", "다정한", "씩씩한", "현명한"]
    nouns = ["학부모", "엄마", "아빠", "보호자", "후원자"]
    suffix = "".join(random.choices(string.digits, k=4))
    return f"{random.choice(adjectives)}{random.choice(nouns)}{suffix}"


async def register_or_login(
    phone_number: str,
    req: ParentVerifyRequest,
    auth_db: AsyncSession,
    service_db: AsyncSession,
) -> tuple[str, str]:
    """
    학부모 인증 완료 후 access_token, refresh_token 반환.
    phone_number는 이 함수 내에서만 사용되고 외부로 노출되지 않는다.
    """
    anon_id = make_anon_id(phone_number)

    # 인증 DB — 학부모 인증 레코드 upsert
    result = await auth_db.execute(
        select(ParentVerification).where(ParentVerification.anon_id == anon_id)
    )
    verification = result.scalar_one_or_none()

    if verification:
        # 재인증 — 학교/학년/반 정보 갱신
        verification.school_code = req.school_code
        verification.school_name = req.school_name
        verification.grade = req.grade
        verification.class_num = req.class_num
        verification.school_type = req.school_type
        verification.is_active = True
    else:
        verification = ParentVerification(
            anon_id=anon_id,
            school_code=req.school_code,
            school_name=req.school_name,
            grade=req.grade,
            class_num=req.class_num,
            school_type=req.school_type,
        )
        auth_db.add(verification)

    await auth_db.commit()

    # 서비스 DB — User upsert (anon_id만 공유, 신원 정보 없음)
    result = await service_db.execute(
        select(User).where(User.anon_id == anon_id)
    )
    user = result.scalar_one_or_none()

    if user:
        user.school_code = req.school_code
        user.school_name = req.school_name
        user.grade = req.grade
        user.class_num = req.class_num
        user.school_type = req.school_type
    else:
        user = User(
            anon_id=anon_id,
            nickname=_random_nickname(),
            school_code=req.school_code,
            school_name=req.school_name,
            grade=req.grade,
            class_num=req.class_num,
            school_type=req.school_type,
        )
        service_db.add(user)

    await service_db.commit()
    await service_db.refresh(user)

    access_token = create_access_token(str(user.id))
    refresh_token = create_refresh_token(str(user.id))
    return access_token, refresh_token
