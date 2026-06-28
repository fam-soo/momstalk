from datetime import datetime, timedelta
from pydantic import BaseModel
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.permissions import require_member
from app.core.rate_limit import RateLimit
from app.core.security import create_access_token, decode_token
from app.db import get_db
from app.models.service_models import User
from app.schemas.auth import (
    CapturePresignResponse,
    CaptureSubmitRequest,
    DevLoginRequest,
    InviteGenerateResponse,
    InviteUseRequest,
    KakaoLoginRequest,
    ParentVerifyRequest,
    RefreshRequest,
    SendSmsRequest,
    TokenResponse,
    VerifySmsRequest,
    VerifySmsResponse,
)
from app.schemas.user import UpdateNicknameRequest, UpdateProfileRequest, UserProfile
from app.services import auth_service, sms_service
from app.services import social_auth_service, capture_service, invite_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/dev/lurker-login", response_model=TokenResponse, include_in_schema=settings.DEBUG)
async def dev_lurker_login(service_db: AsyncSession = Depends(get_db)):
    """[개발 전용] lurker 상태로 즉시 로그인 — 눈팅 모드 UX 테스트용. DEBUG=true 일 때만 동작."""
    if not settings.DEBUG:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    from sqlalchemy import select as sa_select
    from app.core.security import make_anon_id, create_refresh_token
    from app.services.auth_service import _random_nickname

    fake_phone = "01000000000"  # 개발 전용 고정 번호
    anon_id = make_anon_id(fake_phone)

    result = await service_db.execute(sa_select(User).where(User.anon_id == anon_id))
    user = result.scalar_one_or_none()
    if user is None:
        try:
            user = User(
                anon_id=anon_id,
                nickname=_random_nickname(),
                school_code="__pending__",
                school_name="",
                grade=1,
                school_type="",
                social_provider="dev",
                member_grade="lurker",
                auth_pending=False,
            )
            service_db.add(user)
            await service_db.commit()
            await service_db.refresh(user)
        except IntegrityError:
            await service_db.rollback()
            result = await service_db.execute(sa_select(User).where(User.anon_id == anon_id))
            user = result.scalar_one()

    access_token = create_access_token(str(user.id))
    refresh_token = create_refresh_token(str(user.id))
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/dev/approve-me", status_code=status.HTTP_204_NO_CONTENT, include_in_schema=settings.DEBUG)
async def dev_approve_me(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """[개발 전용] 현재 유저를 즉시 정회원으로 승급. 최근 캡처에서 학교 정보를 복사한다."""
    if not settings.DEBUG:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    from sqlalchemy import select as sa_select
    from app.models.service_models import AuthCapture

    capture = (await db.execute(
        sa_select(AuthCapture)
        .where(AuthCapture.user_id == user.id)
        .order_by(AuthCapture.created_at.desc())
    )).scalar_one_or_none()

    user.member_grade = "member"
    user.auth_pending = False
    if capture:
        user.school_code = capture.input_school_code
        user.school_name = capture.input_school_name
        user.grade = capture.input_grade
        if capture.input_class_num:
            user.class_num = capture.input_class_num
        capture.status = "approved"

    await db.commit()


@router.post("/dev/login", response_model=TokenResponse, include_in_schema=settings.DEBUG)
async def dev_login(
    req: DevLoginRequest,
    db: AsyncSession = Depends(get_db),
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
        req.phone_number, parent_req, db
    )
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/sms/send", status_code=status.HTTP_204_NO_CONTENT)
async def send_sms(req: SendSmsRequest, request: Request, db: AsyncSession = Depends(get_db)):
    """SMS 인증코드 발송. 개발 모드에서는 콘솔에 출력."""
    await RateLimit.sms(request)
    await sms_service.send_verification_code(req.phone_number, db)


@router.post("/sms/verify", response_model=VerifySmsResponse)
async def verify_sms(req: VerifySmsRequest, db: AsyncSession = Depends(get_db)):
    """SMS 코드 검증 → 학부모 인증에 쓸 단기 sms_token 반환."""
    try:
        token = await sms_service.verify_code_and_get_token(req.phone_number, req.code, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return VerifySmsResponse(sms_token=token)


@router.post("/parent/verify", response_model=TokenResponse)
async def verify_parent(
    req: ParentVerifyRequest,
    db: AsyncSession = Depends(get_db),
):
    """학부모 인증 완료 → JWT 발급."""
    try:
        phone_number = await sms_service.decode_sms_token(req.sms_token)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    access_token, refresh_token = await auth_service.register_or_login(
        phone_number, req, db
    )
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(req: RefreshRequest, db: AsyncSession = Depends(get_db)):
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
async def get_me(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """현재 로그인 유저 프로필 조회."""
    from sqlalchemy import select as sa_select
    from app.models.service_models import AuthCapture

    # lurker이고 auth_pending=False인 경우 최신 거절 사유 포함
    reject_reason = None
    if user.member_grade == "lurker" and not user.auth_pending:
        latest = (await db.execute(
            sa_select(AuthCapture)
            .where(AuthCapture.user_id == user.id, AuthCapture.status == "rejected")
            .order_by(AuthCapture.created_at.desc())
            .limit(1)
        )).scalar_one_or_none()
        if latest:
            reject_reason = latest.reject_reason

    profile = UserProfile.model_validate(user)
    profile.reject_reason = reject_reason
    return profile


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """회원 탈퇴. 개인정보(anon_id) 즉시 삭제, 게시글·댓글은 익명으로 유지."""
    from sqlalchemy import delete as sa_delete
    from app.models.service_models import ParentVerification

    # 인증 레코드 삭제
    await db.execute(sa_delete(ParentVerification).where(ParentVerification.anon_id == user.anon_id))

    # anon_id·닉네임 삭제, 게시글·댓글 내용은 보존 (익명 처리)
    user.anon_id = f"deleted_{user.id}"
    user.nickname = "탈퇴한 사용자"
    user.fcm_token = None
    user.is_banned = True  # 재활용 방지
    await db.commit()


@router.patch("/me/nickname", response_model=UserProfile)
async def update_nickname(
    req: UpdateNicknameRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user.nickname = req.nickname
    await db.commit()
    await db.refresh(user)
    return user


@router.post("/me/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
async def register_fcm_token(
    body: dict,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """FCM 디바이스 토큰 등록/갱신. 앱 시작 시마다 호출."""
    token = body.get("token", "").strip()
    if not token:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="token 필드가 필요합니다.")
    user.fcm_token = token
    await db.commit()


@router.post("/kakao", response_model=TokenResponse)
async def kakao_login(
    req: KakaoLoginRequest,
    request: Request,
    service_db: AsyncSession = Depends(get_db),
):
    """카카오 AccessToken으로 로그인/회원가입. 신규 유저는 lurker 상태로 생성됨."""
    await RateLimit.login(request)
    try:
        access_token, refresh_token, _user = await social_auth_service.kakao_login(
            req.kakao_access_token, service_db
        )
    except PermissionError as e:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


# ── 캡처 업로드 (가입 루트 A+B) ─────────────────────

class CapturePresignRequest(BaseModel):
    content_type: str = "image/jpeg"


@router.post("/capture/presign", response_model=CapturePresignResponse)
async def capture_presign(
    req: CapturePresignRequest = CapturePresignRequest(),
    user: User = Depends(get_current_user),
):
    """S3 presigned PUT URL 발급. 클라이언트가 이 URL로 직접 이미지를 업로드한다."""
    try:
        url, key = capture_service.generate_presign_url(user.id, req.content_type)
    except RuntimeError as e:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e))
    skip = not settings.AWS_ACCESS_KEY_ID  # S3 미설정 시 클라이언트가 PUT 생략
    return CapturePresignResponse(upload_url=url, s3_key=key, skip_upload=skip)


@router.post("/capture/upload", status_code=status.HTTP_204_NO_CONTENT)
async def capture_upload(
    file: UploadFile = File(..., description="알림장 캡처 이미지 (jpg/png/heic)"),
    school_code: str = Form(...),
    school_name: str = Form(...),
    grade: int = Form(...),
    class_num: int | None = Form(None),
    school_type: str = Form(...),
    region: str = Form(""),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """캡처 이미지 + 학교 정보를 한 번에 제출. Supabase Storage에 저장 후 심사 대기 상태로 전환."""
    _ALLOWED = {"image/jpeg", "image/png", "image/heic", "image/heif"}
    content_type = file.content_type or "image/jpeg"
    if content_type not in _ALLOWED:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="JPG, PNG, HEIC 파일만 업로드 가능합니다.")
    data = await file.read()
    if len(data) > 10 * 1024 * 1024:  # 10 MB
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="파일 크기는 10MB 이하여야 합니다.")
    try:
        storage_key = await capture_service.upload_capture_image(user.id, data, content_type)
    except RuntimeError as e:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e))
    await capture_service.submit_capture(user, storage_key, school_code, school_name, grade, class_num, db, region=region)


@router.post("/capture/submit", status_code=status.HTTP_204_NO_CONTENT)
async def capture_submit(
    req: CaptureSubmitRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """캡처 업로드 완료 후 학교 정보와 함께 제출. 관리자 검토 대기 상태로 전환."""
    await capture_service.submit_capture(
        user, req.s3_key, req.school_code, req.school_name, req.grade, req.class_num, db
    )


# ── 추천 링크 (가입 루트 C) ──────────────────────────

@router.post("/invite/generate", response_model=InviteGenerateResponse)
async def generate_invite(
    user: User = Depends(require_member),
    db: AsyncSession = Depends(get_db),
):
    """정회원만 추천 링크 발급. 발급자의 school_code 고정, 48시간 유효."""
    link = await invite_service.generate_invite(user, db)
    deeplink = f"{settings.INVITE_DEEPLINK_BASE}/{link.token}"
    return InviteGenerateResponse(
        token=link.token,
        expires_at=link.expires_at.isoformat(),
        deeplink=deeplink,
    )


@router.get("/invite/{token}")
async def check_invite(token: str, db: AsyncSession = Depends(get_db)):
    """초대 링크 유효성 미리 확인 (사용 전 정보 표시용)."""
    try:
        link = await invite_service.validate_invite(token, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return {"school_name": link.school_name, "school_code": link.school_code, "expires_at": link.expires_at.isoformat()}


@router.post("/invite/use", status_code=status.HTTP_204_NO_CONTENT)
async def use_invite(
    req: InviteUseRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """초대 링크 사용 → 즉시 정회원 승급."""
    try:
        await invite_service.use_invite(req.token, user, req.grade, req.class_num, db)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.patch("/me/profile", response_model=UserProfile)
async def update_profile(
    req: UpdateProfileRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """지역/학교/학년 변경. 월 1회 제한 (DEBUG 모드에서는 무제한)."""
    if not settings.DEBUG:
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
