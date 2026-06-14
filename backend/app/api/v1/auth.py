from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.security import create_access_token, decode_token
from app.db import get_auth_db, get_service_db
from app.models.service_models import User
from app.schemas.auth import (
    DevLoginRequest,
    ParentVerifyRequest,
    RefreshRequest,
    SendSmsRequest,
    TokenResponse,
    VerifySmsRequest,
    VerifySmsResponse,
)
from app.schemas.user import UpdateNicknameRequest, UpdateProfileRequest, UserProfile
from app.services import auth_service, sms_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/dev/login", response_model=TokenResponse, include_in_schema=settings.DEBUG)
async def dev_login(
    req: DevLoginRequest,
    auth_db: AsyncSession = Depends(get_auth_db),
    service_db: AsyncSession = Depends(get_service_db),
):
    """[개발 전용] 인증번호 없이 바로 로그인. DEBUG=true 일 때만 동작."""
    if not settings.DEBUG:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    parent_req = ParentVerifyRequest(
        sms_token="__dev__",
        region=req.region,
        school_code=req.school_code,
        school_name=req.school_name,
        grade=req.grade,
        school_type=req.school_type,
    )
    access_token, refresh_token = await auth_service.register_or_login(
        req.phone_number, parent_req, auth_db, service_db
    )
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/sms/send", status_code=status.HTTP_204_NO_CONTENT)
async def send_sms(req: SendSmsRequest, auth_db: AsyncSession = Depends(get_auth_db)):
    """SMS 인증코드 발송. 개발 모드에서는 콘솔에 출력."""
    await sms_service.send_verification_code(req.phone_number, auth_db)


@router.post("/sms/verify", response_model=VerifySmsResponse)
async def verify_sms(req: VerifySmsRequest, auth_db: AsyncSession = Depends(get_auth_db)):
    """SMS 코드 검증 → 학부모 인증에 쓸 단기 sms_token 반환."""
    try:
        token = await sms_service.verify_code_and_get_token(req.phone_number, req.code, auth_db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return VerifySmsResponse(sms_token=token)


@router.post("/parent/verify", response_model=TokenResponse)
async def verify_parent(
    req: ParentVerifyRequest,
    auth_db: AsyncSession = Depends(get_auth_db),
    service_db: AsyncSession = Depends(get_service_db),
):
    """
    학부모 인증 완료 → JWT 발급.
    sms_token 안의 전화번호 → HMAC 익명화 → 인증 DB + 서비스 DB 저장.
    """
    try:
        phone_number = await sms_service.decode_sms_token(req.sms_token)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    access_token, refresh_token = await auth_service.register_or_login(
        phone_number, req, auth_db, service_db
    )
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(req: RefreshRequest, service_db: AsyncSession = Depends(get_service_db)):
    """Refresh 토큰으로 새 Access 토큰 발급."""
    try:
        payload = decode_token(req.refresh_token)
        if payload.get("type") != "refresh":
            raise ValueError()
        user_id = payload["sub"]
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="유효하지 않은 refresh token 입니다.")

    new_access = create_access_token(user_id)
    return TokenResponse(access_token=new_access, refresh_token=req.refresh_token)


@router.get("/me", response_model=UserProfile)
async def get_me(user: User = Depends(get_current_user)):
    """현재 로그인 유저 프로필 조회."""
    return user


@router.patch("/me/nickname", response_model=UserProfile)
async def update_nickname(
    req: UpdateNicknameRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    user.nickname = req.nickname
    await db.commit()
    await db.refresh(user)
    return user


@router.patch("/me/profile", response_model=UserProfile)
async def update_profile(
    req: UpdateProfileRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_service_db),
):
    """지역/학교/학년 변경. 월 1회 제한."""
    if user.profile_updated_at and user.profile_updated_at > datetime.utcnow() - timedelta(days=30):
        next_date = user.profile_updated_at + timedelta(days=30)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"월 1회만 변경할 수 있습니다. 다음 변경 가능일: {next_date.strftime('%Y년 %m월 %d일')}",
        )
    user.region = req.region
    user.school_code = req.school_code
    user.school_name = req.school_name
    user.grade = req.grade
    user.school_type = req.school_type
    user.profile_updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(user)
    return user
