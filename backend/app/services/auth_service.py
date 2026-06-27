"""
학부모 인증 서비스.
SMS 토큰(전화번호 증명) → anon_id 생성 → 인증 DB 저장 → 서비스 DB User 생성/조회 → JWT 발급.
인증 DB와 서비스 DB 사이에는 anon_id라는 단방향 해시값만 공유되며,
역추적은 수학적으로 불가능하다.
"""
import random
import re
import string

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.security import make_anon_id, create_access_token, create_refresh_token
from app.models.service_models import ParentVerification, User
from app.schemas.auth import ParentVerifyRequest


def _random_anon_nickname() -> str:
    """완전 익명 게시판용 닉네임 (예: 지혜로운학부모4712)."""
    adjectives = ["용감한", "따뜻한", "지혜로운", "밝은", "든든한", "다정한", "씩씩한", "현명한"]
    nouns = ["학부모", "엄마", "아빠", "보호자", "후원자"]
    suffix = "".join(random.choices(string.digits, k=4))
    return f"{random.choice(adjectives)}{random.choice(nouns)}{suffix}"


def _make_school_short_name(school_name: str) -> str:
    """학교명에서 약칭 추출 (예: '부산광역시 기장군 행복초등학교' → '행복초')."""
    # 초/중/고 앞 최대 4글자 추출
    for suffix in ["초등학교", "중학교", "고등학교", "초", "중", "고"]:
        idx = school_name.find(suffix)
        if idx > 0:
            # suffix 포함 뒤에 붙는 약칭
            label = suffix[:1] if suffix in ("초등학교", "중학교", "고등학교") else suffix
            raw = school_name[:idx].strip()
            # 공백/특수문자 제거 후 마지막 4글자
            raw = re.sub(r"[\s\(\)（）]", "", raw)
            short = raw[-4:] if len(raw) > 4 else raw
            return f"{short}{label}"
    # 매칭 실패 시 앞 5글자
    return school_name[:5]


def _make_certified_nickname(school_short_name: str, existing_users_count: int = 0) -> str:
    """인증 닉네임 생성 (예: 행복초_지혜맘).

    school_short_name은 _make_school_short_name()으로 생성된 학교 약칭.
    """
    adjectives = ["지혜", "씩씩", "따뜻", "밝은", "용감", "다정", "현명", "든든"]
    nouns = ["맘", "아빠", "학부모", "부모님"]
    suffix = "".join(random.choices(string.digits, k=2))
    return f"{school_short_name}_{random.choice(adjectives)}{random.choice(nouns)}{suffix}"


async def register_or_login(
    phone_number: str,
    req: ParentVerifyRequest,
    db: AsyncSession,
) -> tuple[str, str]:
    """학부모 인증 완료 후 access_token, refresh_token 반환."""
    anon_id = make_anon_id(phone_number)

    # 학부모 인증 레코드 upsert
    result = await db.execute(
        select(ParentVerification).where(ParentVerification.anon_id == anon_id)
    )
    verification = result.scalar_one_or_none()

    if verification:
        verification.school_code = req.school_code
        verification.school_name = req.school_name
        verification.grade = req.grade
        verification.school_type = req.school_type
        verification.is_active = True
    else:
        verification = ParentVerification(
            anon_id=anon_id,
            school_code=req.school_code,
            school_name=req.school_name,
            grade=req.grade,
            class_num=1,
            school_type=req.school_type,
        )
        db.add(verification)

    # User upsert
    result = await db.execute(
        select(User).where(User.anon_id == anon_id)
    )
    user = result.scalar_one_or_none()

    school_short = _make_school_short_name(req.school_name)

    if user:
        user.region = req.region
        user.school_code = req.school_code
        user.school_name = req.school_name
        user.grade = req.grade
        user.school_type = req.school_type
        user.school_short_name = school_short
        if not user.certified_nickname:
            user.certified_nickname = _make_certified_nickname(school_short)
    else:
        certified_nick = _make_certified_nickname(school_short)
        user = User(
            anon_id=anon_id,
            nickname=_random_anon_nickname(),
            certified_nickname=certified_nick,
            school_short_name=school_short,
            region=req.region,
            school_code=req.school_code,
            school_name=req.school_name,
            grade=req.grade,
            school_type=req.school_type,
        )
        db.add(user)

    await db.commit()
    await db.refresh(user)

    access_token = create_access_token(str(user.id))
    refresh_token = create_refresh_token(str(user.id))
    return access_token, refresh_token
