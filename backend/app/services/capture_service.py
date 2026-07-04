"""
알림장 캡처 업로드 & 관리자 대조 승인 서비스.

흐름 (Supabase Storage):
  1. 유저가 POST /auth/capture/upload (multipart) → 백엔드가 Supabase Storage에 저장
  2. auth_captures 행 생성 (storage_key 보관)
  3. 관리자 GET /admin/captures/{id}/image → 백엔드가 Supabase에서 가져와 프록시
  4. 승인 시 member_grade = 'member', 파일 삭제
"""
import uuid
from datetime import datetime

import httpx
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.config import settings
from app.core.fcm import send_push
from app.models.service_models import AdminAction, AuthCapture, User, UserChild

_SUPABASE_BUCKET = "captures"

_ALLOWED_CONTENT_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/heic": "heic",
    "image/heif": "heif",
}


def _storage_available() -> bool:
    return bool(settings.SUPABASE_URL and settings.SUPABASE_SERVICE_KEY)


def _storage_path(user_id: int, content_type: str) -> str:
    ext = _ALLOWED_CONTENT_TYPES.get(content_type, "jpg")
    return f"{user_id}/{uuid.uuid4().hex}.{ext}"


async def upload_capture_image(user_id: int, data: bytes, content_type: str) -> str:
    """Supabase Storage에 이미지 업로드 → storage_key 반환."""
    if content_type not in _ALLOWED_CONTENT_TYPES:
        content_type = "image/jpeg"

    if not _storage_available():
        # 개발 환경: 실제 저장 없이 더미 키 반환
        return f"dev/{user_id}/{uuid.uuid4().hex}.jpg"

    path = _storage_path(user_id, content_type)  # e.g. "1/abc123.jpg" (버킷명 제외)
    url = f"{settings.SUPABASE_URL}/storage/v1/object/{_SUPABASE_BUCKET}/{path}"
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(url, content=data, headers={
            "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
            "Content-Type": content_type,
        })
        if resp.status_code not in (200, 201):
            raise RuntimeError(f"Supabase Storage 업로드 실패: {resp.status_code} {resp.text}")
    return path


async def get_capture_image(storage_key: str) -> tuple[bytes, str]:
    """Supabase Storage에서 이미지 다운로드 → (bytes, content_type)."""
    if not _storage_available():
        raise RuntimeError("Supabase Storage 미설정 (SUPABASE_URL / SUPABASE_SERVICE_KEY)")

    # 구 S3 키가 "captures/..." 형태로 저장된 경우 버킷명 중복 방지
    path = storage_key.removeprefix(f"{_SUPABASE_BUCKET}/")
    url = f"{settings.SUPABASE_URL}/storage/v1/object/{_SUPABASE_BUCKET}/{path}"
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(url, headers={
            "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
        })
        if resp.status_code == 404:
            raise FileNotFoundError("이미지 파일을 찾을 수 없습니다.")
        resp.raise_for_status()
    content_type = resp.headers.get("content-type", "image/jpeg").split(";")[0]
    return resp.content, content_type


def _delete_storage_object(storage_key: str) -> None:
    """동기 삭제 (approve/reject 시 호출 — fire-and-forget 방식)."""
    if not _storage_available() or storage_key.startswith("dev/"):
        return
    import threading

    def _do():
        import asyncio
        asyncio.run(_delete_async(storage_key))

    threading.Thread(target=_do, daemon=True).start()


async def _delete_async(storage_key: str) -> None:
    url = f"{settings.SUPABASE_URL}/storage/v1/object/{_SUPABASE_BUCKET}"
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            await client.delete(
                f"{url}/{storage_key}",
                headers={"Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}"},
            )
    except Exception:
        pass


async def submit_capture(
    user: User,
    storage_key: str,
    school_code: str,
    school_name: str,
    grade: int,
    class_num: int | None,
    db: AsyncSession,
    region: str = "",
    school_type: str = "",
    capture_type: str = "initial",
) -> AuthCapture:
    """캡처 ���출 → auth_captures 행 생성.
    capture_type='initial': 최초 가입 인증 (user.auth_pending = True)
    capture_type='child_add': 자녀 추가 인증 (기존 캡처 덮어쓰기 없이 새 행 추가)
    """
    if capture_type == "initial":
        # 최초 가입: 기존 pending 캡처가 있으면 덮어쓰기
        existing = (await db.execute(
            select(AuthCapture).where(
                AuthCapture.user_id == user.id,
                AuthCapture.capture_type == "initial",
            )
        )).scalar_one_or_none()
        if existing:
            _delete_storage_object(existing.s3_key)
            existing.s3_key = storage_key
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
                s3_key=storage_key,
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
            _delete_storage_object(existing.s3_key)
            existing.s3_key = storage_key
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
                s3_key=storage_key,
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

    _delete_storage_object(capture.s3_key)

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

    _delete_storage_object(capture.s3_key)

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
