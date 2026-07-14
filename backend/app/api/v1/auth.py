from datetime import datetime, timedelta
from typing import Optional
from pydantic import BaseModel
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.image_sniff import sniff_image_mime
from app.core.permissions import require_member
from app.core.rate_limit import RateLimit
from app.core.security import create_access_token, decode_token
from app.db import get_db
from app.models.service_models import User, UserChild, UserFcmToken
from app.schemas.auth import (
    AdminLoginRequest,
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
from app.schemas.user import UpdateNicknameRequest, UpdateProfileRequest, UserProfile, AddChildRequest, ChildProfile, LearningGoalsUpdate
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


def _user_profile_with_active_child(user: User) -> UserProfile:
    """지역/학교/학년은 activeChild가 있으면 그 자녀 기준으로 덮어써서 반환한다.

    users.region/school_name/grade/school_type은 다자녀 지원 이전의 레거시
    필드로, 지금은 "첫 자녀 등록 시"에만 동기화된다. active_child_id로 다른
    자녀를 선택한 경우에도 이 필드들을 그대로 내려주면 지역/학교/학원 탭이
    내정보에서 선택한 자녀와 무관하게 예전 자녀 기준으로 보이는 문제가
    생기므로, 모든 프로필 응답에서 activeChild 기준으로 통일한다.
    """
    profile = UserProfile.model_validate(user)
    active = user.active_child
    if active:
        profile.region = active.region or profile.region
        profile.school_name = active.school_name or profile.school_name
        profile.grade = active.grade or profile.grade
        profile.school_type = active.school_type or profile.school_type
        profile.learning_goals = active.learning_goals or profile.learning_goals
        if active.school_type == "preschool" and active.expected_entry_year:
            from datetime import date
            profile.needs_school_verification = date.today().year >= active.expected_entry_year
    return profile


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

    from app.services.temperature_service import to_celsius
    profile = _user_profile_with_active_child(user)
    profile.reject_reason = reject_reason
    profile.temperature = to_celsius(user.manner_score)
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
    await db.execute(sa_delete(UserFcmToken).where(UserFcmToken.user_id == user.id))
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
    return _user_profile_with_active_child(user)


@router.post("/me/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
async def register_fcm_token(
    body: dict,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """FCM 디바이스 토큰 등록/갱신. 앱(기기)마다 호출 — 기기별로 별도 행에 저장되므로
    같은 계정을 여러 기기에서 동시에 켜둬도 모두 알림을 받을 수 있다."""
    from sqlalchemy import select as sa_select

    token = body.get("token", "").strip()
    if not token:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="token 필드가 필요합니다.")

    existing = (await db.execute(
        sa_select(UserFcmToken).where(UserFcmToken.token == token)
    )).scalar_one_or_none()
    if existing:
        # 같은 토큰이 다른 계정으로 재등록되는 경우(기기 로그아웃 후 재로그인 등) 소유자를 갱신
        existing.user_id = user.id
    else:
        db.add(UserFcmToken(user_id=user.id, token=token))
    await db.commit()


@router.delete("/me/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
async def clear_fcm_token(
    body: dict | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """알림 끄기 — 요청에 token이 있으면 그 기기 하나만, 없으면 이 계정의
    모든 기기 토큰을 삭제한다 (브라우저 알림 권한 자체는 그대로 유지됨)."""
    from sqlalchemy import delete as sa_delete

    token = (body or {}).get("token", "").strip()
    if token:
        await db.execute(
            sa_delete(UserFcmToken).where(UserFcmToken.user_id == user.id, UserFcmToken.token == token)
        )
    else:
        await db.execute(sa_delete(UserFcmToken).where(UserFcmToken.user_id == user.id))
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
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


# ── 캡처 업로드 (가입 루트 A+B) ─────────────────────
# 이미지는 별도 오브젝트 스토리지 없이 auth_captures.image_data(BYTEA)에 직접
# 저장한다 — 업로드 즉시 DB 트랜잭션 하나로 끝나 외부 스토리지 왕복에서
# 발생하던 실패 지점이 사라진다. 심사(승인/반려) 시 같은 트랜잭션에서 바로
# 비워지므로 별도 삭제 요청도 필요 없다.

@router.post("/capture/upload", status_code=status.HTTP_204_NO_CONTENT)
async def capture_upload(
    file: UploadFile = File(..., description="알림장 캡처 이미지 (jpg/png/heic)"),
    school_code: str | None = Form(None),
    school_name: str | None = Form(None),
    grade: int | None = Form(None),
    class_num: int | None = Form(None),
    school_type: str = Form(...),
    region: str = Form(""),
    capture_type: str = Form("initial"),
    expected_entry_year: int | None = Form(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """캡처 이미지 + 학교 정보를 한 번에 제출. DB에 저장 후 심사 대기 상태로 전환.

    school_type="preschool"은 학교가 없는 미취학 가입이라 school_code/school_name/
    grade 없이도 제출 가능 — 지역(region) 인증만으로 진행한다.
    """
    if school_type != "preschool" and not (school_code and school_name and grade):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="school_code/school_name/grade는 미취학이 아니면 필수입니다.")
    data = await file.read()
    if len(data) > 10 * 1024 * 1024:  # 10 MB
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="파일 크기는 10MB 이하여야 합니다.")
    # 클라이언트가 보낸 Content-Type 헤더는 신뢰하지 않고 실제 파일 바이트로 포맷을 판별한다.
    # (Dio/http 패키지 등 클라이언트 구현체 교체 시 헤더 누락으로 인한 400 재발 방지)
    content_type = sniff_image_mime(data)
    if content_type is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="JPG, PNG, HEIC 파일만 업로드 가능합니다.")
    await capture_service.submit_capture(
        user, data, content_type, school_code, school_name, grade, class_num, db,
        region=region, school_type=school_type, capture_type=capture_type,
        expected_entry_year=expected_entry_year,
    )


@router.post("/capture/submit", status_code=status.HTTP_204_NO_CONTENT)
async def capture_submit(
    req: CaptureSubmitRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """[DEV] 이미지 없이 학교 정보만으로 제출 (더미 s3_key). 관리자 검토 대기 상태로 전환."""
    await capture_service.submit_capture(
        user, None, None, req.school_code, req.school_name, req.grade, req.class_num, db,
        region=req.region, school_type=req.school_type, expected_entry_year=req.expected_entry_year,
    )


# ── 추천 링크 (가입 루트 C) ──────────────────────────

class InviteGenerateRequest(BaseModel):
    child_id: Optional[int] = None  # 다자녀 시 특정 자녀 지정. None이면 active_child 사용


@router.post("/invite/generate", response_model=InviteGenerateResponse)
async def generate_invite(
    req: InviteGenerateRequest = InviteGenerateRequest(),
    user: User = Depends(require_member),
    db: AsyncSession = Depends(get_db),
):
    """정회원만 추천 링크 발급. active_child(또는 지정 child_id) 학교 고정, 24시간·최대 10명."""
    try:
        link = await invite_service.generate_invite(user, db, child_id=req.child_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    deeplink = f"{settings.INVITE_DEEPLINK_BASE}/{link.token}"
    return InviteGenerateResponse(
        token=link.token,
        expires_at=link.expires_at.isoformat(),
        deeplink=deeplink,
        school_name=link.school_name,
        max_uses=link.max_uses,
    )


@router.get("/invite/{token}")
async def check_invite(token: str, db: AsyncSession = Depends(get_db)):
    """초대 링크 정보 표시 (사용 전 미리 보기).
    정원 마감 여부와 관계없이 링크 존재·만료 여부만 확인한다.
    실제 정원 확인(원자적 처리)은 POST /invite/use 에서 수행."""
    link = await invite_service.get_invite(token, db)
    if not link:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="유효하지 않은 초대 링크입니다.")
    from datetime import datetime
    if datetime.utcnow() > link.expires_at:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="만료된 초대 링크입니다.")
    return {
        "school_name": link.school_name,
        "school_code": link.school_code,
        "school_type": link.school_type,
        "expires_at": link.expires_at.isoformat(),
        "max_uses": link.max_uses,
        "use_count": link.use_count,
        "is_full": link.use_count >= link.max_uses,
        # 하위 호환: 기존 프론트가 is_used를 참조할 수 있어 정원 마감 여부로 매핑
        "is_used": link.use_count >= link.max_uses,
    }


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
    """지역/학교/학년 변경. 월 1회 제한 (DEBUG 모드 또는 관리자가 인증 면제(is_trusted)한 사용자는 무제한)."""
    if not settings.DEBUG and not user.is_trusted:
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
    # 현재 활성 자녀가 있으면 그 자녀 기록도 함께 갱신한다. active_child가
    # 있을 때 응답은 activeChild 기준으로 내려가므로(_user_profile_with_active_child),
    # 여기서 deprecated 필드만 바꾸면 화면상 변경이 반영되지 않는 것처럼 보인다.
    if user.active_child_id:
        active = user.active_child
        if active:
            active.region = req.region
            active.school_code = req.school_code
            active.school_name = req.school_name
            active.grade = req.grade
            active.school_type = req.school_type
    await db.commit()
    await db.refresh(user)
    return _user_profile_with_active_child(user)


@router.post("/admin/login", response_model=TokenResponse)
async def admin_login(
    req: AdminLoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """관리자 전용 로그인 (username + password). 카카오 인증 불필요."""
    from sqlalchemy import select as sa_select
    from app.core.security import verify_password, create_refresh_token

    result = await db.execute(
        sa_select(User).where(User.admin_username == req.username, User.is_admin == True)
    )
    user = result.scalar_one_or_none()
    if not user or not user.admin_password_hash or not verify_password(req.password, user.admin_password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="아이디 또는 비밀번호가 올바르지 않습니다.")

    access_token = create_access_token(str(user.id))
    refresh_token = create_refresh_token(str(user.id))
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/admin/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def admin_change_password(
    current_password: str,
    new_password: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """관리자 비밀번호 변경."""
    from app.core.security import verify_password, hash_password
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="관리자만 사용 가능합니다.")
    if not user.admin_password_hash or not verify_password(current_password, user.admin_password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="현재 비밀번호가 올바르지 않습니다.")
    if len(new_password) < 8:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="비밀번호는 8자 이상이어야 합니다.")
    user.admin_password_hash = hash_password(new_password)
    await db.commit()


# ── 자녀 관리 ─────────────────────────────────────────────────

@router.get("/me/children", response_model=list[ChildProfile])
async def list_children(
    user: User = Depends(get_current_user),
):
    """현재 유저의 자녀 목록 조회."""
    return list(user.children)


@router.post("/me/children", response_model=ChildProfile, status_code=status.HTTP_201_CREATED)
async def add_child(
    req: AddChildRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """자녀 추가 (최대 5명). 사진 인증 없이 즉시 추가 — 관리자가 인증 면제(is_trusted)한 사용자 전용."""
    if not user.is_trusted and not user.is_admin:
        raise HTTPException(status_code=403, detail="사진 인증이 필요합니다. 자녀 추가 화면에서 인증 사진을 제출해주세요.")
    if len(user.children) >= 5:
        raise HTTPException(status_code=400, detail="자녀는 최대 5명까지 등록할 수 있습니다.")

    child = UserChild(
        user_id=user.id,
        school_code=req.school_code,
        school_name=req.school_name,
        grade=req.grade,
        class_num=req.class_num,
        school_type=req.school_type,
        region=req.region,
        expected_entry_year=req.expected_entry_year,
    )
    db.add(child)
    await db.flush()

    # 첫 자녀면 active_child로 자동 설정
    if user.active_child_id is None:
        user.active_child_id = child.id

    await db.commit()
    await db.refresh(child)
    return child


@router.patch("/me/children/{child_id}", response_model=ChildProfile)
async def update_child(
    child_id: int,
    req: AddChildRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """자녀 정보 수정."""
    child = next((c for c in user.children if c.id == child_id), None)
    if not child:
        raise HTTPException(status_code=404, detail="자녀 정보를 찾을 수 없습니다.")

    child.school_code = req.school_code
    child.school_name = req.school_name
    child.grade = req.grade
    child.class_num = req.class_num
    child.school_type = req.school_type
    if req.region:
        child.region = req.region
    if req.expected_entry_year:
        child.expected_entry_year = req.expected_entry_year

    await db.commit()
    await db.refresh(child)
    return child


@router.patch("/me/children/{child_id}/learning-goals", response_model=ChildProfile)
async def update_learning_goals(
    child_id: int,
    req: LearningGoalsUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """학원 추천용 학습 목표(선행/심화/내신/수능/경시/영재) 설정.

    가입 시엔 선택 입력이지만, 학원 검색 화면 진입 시 프론트에서 이 값이
    비어있으면 입력을 요구한다(academy_screen.dart _ensureLearningGoals 참고)."""
    child = next((c for c in user.children if c.id == child_id), None)
    if not child:
        raise HTTPException(status_code=404, detail="자녀 정보를 찾을 수 없습니다.")

    child.learning_goals = req.learning_goals
    await db.commit()
    await db.refresh(child)
    return child


@router.delete("/me/children/{child_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_child(
    child_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """자녀 삭제. active_child이면 다른 자녀로 전환."""
    child = next((c for c in user.children if c.id == child_id), None)
    if not child:
        raise HTTPException(status_code=404, detail="자녀 정보를 찾을 수 없습니다.")

    if user.active_child_id == child_id:
        # 다른 자녀로 전환
        other = next((c for c in user.children if c.id != child_id), None)
        user.active_child_id = other.id if other else None

    await db.delete(child)
    await db.commit()


@router.post("/me/active-child/{child_id}", response_model=UserProfile)
async def set_active_child(
    child_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """활성 자녀 전환."""
    child = next((c for c in user.children if c.id == child_id), None)
    if not child:
        raise HTTPException(status_code=404, detail="자녀 정보를 찾을 수 없습니다.")

    user.active_child_id = child_id
    await db.commit()
    await db.refresh(user)
    return _user_profile_with_active_child(user)
