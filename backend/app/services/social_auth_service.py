"""
카카오 로그인 서비스.
카카오 서버에서 전화번호 동의항목을 포함한 사용자 정보를 가져와
anon_id(HMAC)로 변환 후 서비스 DB에 User를 생성/조회한다.

전화번호는 이 함수 내에서만 사용되고 서비스 DB에 저장되지 않는다.
"""
import httpx

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.security import make_anon_id, create_access_token, create_refresh_token
from app.models.service_models import User
from app.services.auth_service import _random_anon_nickname as _random_nickname


KAKAO_ME_URL = "https://kapi.kakao.com/v2/user/me"

# 미성년자 연령대 (카카오 age_range 값)
_MINOR_AGE_RANGES = {"1~9", "10~14", "15~19"}


async def _fetch_kakao_profile(kakao_access_token: str) -> dict:
    """카카오 API로 사용자 정보 조회. age_range로 미성년자 가입 차단."""
    headers = {"Authorization": f"Bearer {kakao_access_token}"}
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(KAKAO_ME_URL, headers=headers)
    if resp.status_code != 200:
        raise ValueError(f"카카오 API 오류: {resp.status_code}")
    data = resp.json()
    kakao_id = str(data["id"])

    kakao_account = data.get("kakao_account") or {}
    age_range = kakao_account.get("age_range")

    if age_range and age_range in _MINOR_AGE_RANGES:
        raise PermissionError("미성년자는 MomsTalk에 가입할 수 없습니다.")

    return {"kakao_id": kakao_id}



async def kakao_login(
    kakao_access_token: str,
    service_db: AsyncSession,
) -> tuple[str, str, User]:
    """
    카카오 AccessToken → JWT(access, refresh) 반환.
    신규 유저는 member_grade='lurker', auth_pending=False로 생성된다.
    """
    profile = await _fetch_kakao_profile(kakao_access_token)
    anon_id = make_anon_id(profile["kakao_id"])

    result = await service_db.execute(select(User).where(User.anon_id == anon_id))
    user = result.scalar_one_or_none()

    if not user:
        user = User(
            anon_id=anon_id,
            nickname=_random_nickname(),
            # school 정보는 이후 단계(캡처/초대)에서 채움
            school_code="__pending__",
            school_name="",
            grade=1,
            school_type="",
            social_provider="kakao",
            member_grade="lurker",
            auth_pending=False,
        )
        service_db.add(user)
        await service_db.commit()
        await service_db.refresh(user)
    else:
        # 기존 유저 — 소셜 프로바이더 업데이트
        if not user.social_provider:
            user.social_provider = "kakao"
            await service_db.commit()
            await service_db.refresh(user)

    access_token = create_access_token(str(user.id))
    refresh_token = create_refresh_token(str(user.id))
    return access_token, refresh_token, user
