"""
알림장 캡처 업로드 & 관리자 대조 승인 서비스.

흐름 (Postgres 직접 저장):
  1. 유저가 POST /auth/capture/upload (multipart) → 이미지 바이트를 auth_captures 행에 그대로 저장
  2. 관리자 GET /admin/captures/{id}/image → DB에서 바로 읽어 반환 (외부 스토리지 왕복 없음)
  3. 승인/반려 시 image_data를 즉시 비움 (같은 트랜잭션 — 별도 삭제 요청 불필요)

이미지는 가입 인증용으로만 잠깐 보관되는 작은 파일(리사이즈된 사진)이고 심사
직후 삭제되는 단명 데이터라, 별도 오브젝트 스토리지(Supabase 등) 없이 단일
Postgres DB에 BYTEA로 저장해 업로드~심사 흐름의 네트워크 홉과 실패 지점을
줄였다. (과거 Supabase Storage 왕복이 반복적인 업로드 오류의 원인 중 하나였음)
"""
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.fcm import send_push
from app.models.service_models import AdminAction, AuthCapture, User, UserChild

_ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/heic", "image/heif"}


async def submit_capture(
    user: User,
    image_data: bytes | None,
    image_content_type: str | None,
    school_code: str,
    school_name: str,
    grade: int,
    class_num: int | None,
    db: AsyncSession,
    region: str = "",
    school_type: str = "",
    capture_type: str = "initial",
) -> AuthCapture:
    """캡처 이미지 + 학교 정보 제출 → auth_captures 행 생성.
    capture_type='initial': 최초 가입 인증 (user.auth_pending = True)
    capture_type='child_add': 자녀 추가 인증 (기존 캡처 덮어쓰기 없이 새 행 추가)
    """
    if image_content_type not in _ALLOWED_CONTENT_TYPES:
        image_content_type = "image/jpeg" if image_data else None

    if capture_type == "initial":
        # 최초 가입: 기존 pending 캡처가 있으면 덮어쓰기
        existing = (await db.execute(
            select(AuthCapture).where(
                AuthCapture.user_id == user.id,
                AuthCapture.capture_type == "initial",
            )
        )).scalar_one_or_none()
        if existing:
            existing.image_data = image_data
            existing.image_content_type = image_content_type
            existing.input_school_code = school_code
            existing.input_school_name = school_name
            existing.input_grade = grade
            existing.input_class_num = class_num
            existing.input_school_type = school_type or None
            existing.input_region = region or None
            existing.status = "pending"
            existing.reviewed_by = None
            existing.reviewed_at = None
            existing.reject_reason = None
            existing.created_at = datetime.utcnow()
            capture = existing
        else:
            capture = AuthCapture(
                user_id=user.id,
                capture_type="initial",
                image_data=image_data,
                image_content_type=image_content_type,
                input_school_code=school_code,
                input_school_name=school_name,
                input_grade=grade,
                input_class_num=class_num,
                input_school_type=school_type or None,
                input_region=region or None,
            )
            db.add(capture)
        if region:
            user.region = region
        user.auth_pending = True
        user.auth_route = "capture"
    else:
        # 자녀 추가: 항상 새 행 추가 (같은 학교 기존 pending 있으면 덮어쓰기)
        existing = (await db.execute(
            select(AuthCapture).where(
                AuthCapture.user_id == user.id,
                AuthCapture.capture_type == "child_add",
                AuthCapture.input_school_code == school_code,
                AuthCapture.status == "pending",
            )
        )).scalar_one_or_none()
        if existing:
            existing.image_data = image_data
            existing.image_content_type = image_content_type
            existing.input_grade = grade
            existing.input_class_num = class_num
            existing.input_school_type = school_type or None
            existing.input_region = region or None
            existing.reviewed_by = None
            existing.reviewed_at = None
            existing.reject_reason = None
            existing.created_at = datetime.utcnow()
            capture = existing
        else:
            capture = AuthCapture(
                user_id=user.id,
                capture_type="child_add",
                image_data=image_data,
                image_content_type=image_content_type,
                input_school_code=school_code,
                input_school_name=school_name,
                input_grade=grade,
                input_class_num=class_num,
                input_school_type=school_type or None,
                input_region=region or None,
            )
            db.add(capture)

    await db.commit()
    await db.refresh(capture)

    # 신뢰된 사용자: 심사 없이 즉시 승인 처리
    if getattr(user, "is_trusted", False):
        await _auto_approve_trusted(user, capture, school_code, school_name, grade, class_num, school_type, region, db)

    return capture


async def _auto_approve_trusted(
    user: User,
    capture: AuthCapture,
    school_code: str,
    school_name: str,
    grade: int,
    class_num: int | None,
    school_type: str,
    region: str,
    db: AsyncSession,
) -> None:
    """is_trusted 유저의 캡처를 즉시 승인."""
    from app.models.service_models import UserChild
    capture.status = "approved"
    capture.reviewed_at = datetime.utcnow()
    capture.image_data = None
    capture.image_content_type = None

    if capture.capture_type == "child_add":
        from sqlalchemy import select as _select
        existing_child = (await db.execute(
            _select(UserChild).where(
                UserChild.user_id == user.id,
                UserChild.school_code == school_code,
            )
        )).scalar_one_or_none()
        if existing_child:
            existing_child.grade = grade
            existing_child.class_num = class_num
            existing_child.school_type = school_type or existing_child.school_type
        else:
            child = UserChild(
                user_id=user.id,
                school_code=school_code,
                school_name=school_name,
                grade=grade,
                class_num=class_num,
                school_type=school_type or None,
                region=region or user.region,
            )
            db.add(child)
            await db.flush()
            if not user.active_child_id:
                user.active_child_id = child.id
    else:
        user.member_grade = "member"
        user.auth_pending = False
        user.school_code = school_code
        user.school_name = school_name
        user.grade = grade
        if class_num:
            user.class_num = class_num

    await db.commit()


async def approve_capture(capture_id: int, admin: User, db: AsyncSession) -> None:
    capture = (await db.execute(
        select(AuthCapture).where(AuthCapture.id == capture_id)
    )).scalar_one_or_none()
    if not capture or capture.status != "pending":
        raise ValueError("처리할 수 없는 캡처입니다.")

    user = (await db.execute(select(User).where(User.id == capture.user_id))).scalar_one_or_none()
    if not user:
        raise ValueError("대상 유저를 찾을 수 없습니다.")

    capture.status = "approved"
    capture.reviewed_by = admin.id
    capture.reviewed_at = datetime.utcnow()
    capture.image_data = None
    capture.image_content_type = None

    if capture.capture_type == "child_add":
        # 자녀 추가 승인: UserChild 생성 또는 학년 업데이트
        existing_child = (await db.execute(
            select(UserChild).where(
                UserChild.user_id == user.id,
                UserChild.school_code == capture.input_school_code,
            )
        )).scalar_one_or_none()

        if existing_child:
            existing_child.grade = capture.input_grade
            if capture.input_class_num:
                existing_child.class_num = capture.input_class_num
            child = existing_child
        else:
            child = UserChild(
                user_id=user.id,
                school_code=capture.input_school_code,
                school_name=capture.input_school_name,
                grade=capture.input_grade,
                class_num=capture.input_class_num,
                school_type=capture.input_school_type,
                region=capture.input_region or user.region,
            )
            db.add(child)
            await db.flush()

        if not user.active_child_id:
            user.active_child_id = child.id
            # 첫 자녀인 경우에만 deprecated 필드 동기화
            user.school_code = capture.input_school_code
            user.school_name = capture.input_school_name
            user.grade = capture.input_grade

        push_title = "자녀 학교 인증 완료!"
        push_body = f"{capture.input_school_name} 학부모로 확인되었습니다."
    else:
        # 최초 가입 승인: 정회원 승급
        user.member_grade = "member"
        user.auth_pending = False
        user.school_code = capture.input_school_code
        user.school_name = capture.input_school_name
        user.grade = capture.input_grade
        if capture.input_class_num:
            user.class_num = capture.input_class_num

        push_title = "가입 승인 완료!"
        push_body = "맘스토크 정회원이 되었습니다."

    db.add(AdminAction(
        admin_id=admin.id,
        action_type="approve_capture",
        target_type="capture",
        target_id=capture.id,
        detail=capture.capture_type,
    ))
    await db.commit()

    if user.fcm_token:
        await send_push(user.fcm_token, title=push_title, body=push_body, data={"type": "auth_approved"})


async def reject_capture(capture_id: int, admin: User, reason: str, db: AsyncSession) -> None:
    capture = (await db.execute(
        select(AuthCapture).where(AuthCapture.id == capture_id)
    )).scalar_one_or_none()
    if not capture or capture.status != "pending":
        raise ValueError("처리할 수 없는 캡처입니다.")

    user = (await db.execute(select(User).where(User.id == capture.user_id))).scalar_one_or_none()

    capture.status = "rejected"
    capture.reviewed_by = admin.id
    capture.reviewed_at = datetime.utcnow()
    capture.reject_reason = reason
    capture.image_data = None
    capture.image_content_type = None

    if user and capture.capture_type == "initial":
        user.auth_pending = False

    db.add(AdminAction(
        admin_id=admin.id,
        action_type="reject_capture",
        target_type="capture",
        target_id=capture.id,
        detail=reason,
    ))
    await db.commit()

    if user and user.fcm_token:
        title = "자녀 추가 심사 결과" if capture.capture_type == "child_add" else "가입 심사 결과"
        await send_push(
            user.fcm_token,
            title=title,
            body=f"심사가 반려되었습니다. 사유: {reason[:60]}",
            data={"type": "auth_rejected"},
        )


async def list_pending_captures(db: AsyncSession) -> list[AuthCapture]:
    result = await db.execute(
        select(AuthCapture).where(AuthCapture.status == "pending").order_by(AuthCapture.created_at.asc())
    )
    return result.scalars().all()
