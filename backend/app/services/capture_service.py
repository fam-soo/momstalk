"""
알림장 캡처 업로드 & 관리자 대조 승인 서비스.

흐름:
  1. 유저가 /auth/capture/presign 요청 → S3 presigned PUT URL 발급
  2. 클라이언트가 S3로 직접 업로드
  3. 유저가 /auth/capture/submit 으로 s3_key + 학교정보 제출 → auth_captures 행 생성
  4. 관리자가 /admin/captures 에서 검토 → approve/reject
  5. 승인 시 user.member_grade = 'member', user.auth_pending = False
     거절 시 user.auth_pending = False, s3_key 삭제
"""
import uuid
from datetime import datetime

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.config import settings
from app.core.fcm import send_push
from app.models.service_models import AdminAction, AdminUser, AuthCapture, User


def _s3_client():
    return boto3.client(
        "s3",
        region_name=settings.AWS_REGION,
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
    )


def generate_presign_url(user_id: int) -> tuple[str, str]:
    """S3 presigned PUT URL 발급. (url, s3_key) 반환."""
    if not settings.AWS_ACCESS_KEY_ID:
        # 개발 환경 — 더미 반환
        key = f"captures/{user_id}/{uuid.uuid4().hex}.jpg"
        return ("http://localhost:9000/presign-dummy", key)
    key = f"captures/{user_id}/{uuid.uuid4().hex}.jpg"
    try:
        url = _s3_client().generate_presigned_url(
            "put_object",
            Params={"Bucket": settings.AWS_S3_BUCKET, "Key": key, "ContentType": "image/jpeg"},
            ExpiresIn=600,
        )
        return url, key
    except (BotoCoreError, ClientError) as e:
        raise RuntimeError(f"S3 presign 실패: {e}")


def _delete_s3_object(key: str) -> None:
    if not settings.AWS_ACCESS_KEY_ID:
        return
    try:
        _s3_client().delete_object(Bucket=settings.AWS_S3_BUCKET, Key=key)
    except Exception:
        pass


async def submit_capture(
    user: User,
    s3_key: str,
    school_code: str,
    school_name: str,
    grade: int,
    class_num: int | None,
    db: AsyncSession,
) -> AuthCapture:
    """캡처 제출 → auth_captures 행 생성, user.auth_pending = True."""
    # 기존 pending 캡처가 있으면 덮어씀
    existing = (await db.execute(
        select(AuthCapture).where(AuthCapture.user_id == user.id)
    )).scalar_one_or_none()

    if existing:
        _delete_s3_object(existing.s3_key)
        existing.s3_key = s3_key
        existing.input_school_code = school_code
        existing.input_school_name = school_name
        existing.input_grade = grade
        existing.input_class_num = class_num
        existing.status = "pending"
        existing.reviewed_by = None
        existing.reviewed_at = None
        existing.reject_reason = None
        existing.created_at = datetime.utcnow()
        capture = existing
    else:
        capture = AuthCapture(
            user_id=user.id,
            s3_key=s3_key,
            input_school_code=school_code,
            input_school_name=school_name,
            input_grade=grade,
            input_class_num=class_num,
        )
        db.add(capture)

    user.auth_pending = True
    user.auth_route = "capture"
    await db.commit()
    await db.refresh(capture)
    return capture


async def approve_capture(
    capture_id: int,
    admin: AdminUser,
    db: AsyncSession,
) -> None:
    """관리자 승인 → user.member_grade = 'member', S3 파일 삭제."""
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

    user.member_grade = "member"
    user.auth_pending = False
    user.school_code = capture.input_school_code
    user.school_name = capture.input_school_name
    user.grade = capture.input_grade
    if capture.input_class_num:
        user.class_num = capture.input_class_num

    db.add(AdminAction(
        admin_id=admin.id,
        action_type="approve_capture",
        target_type="capture",
        target_id=capture.id,
    ))
    await db.commit()

    _delete_s3_object(capture.s3_key)

    if user.fcm_token:
        await send_push(user.fcm_token, title="가입 승인 완료!", body="맘스토크 정회원이 되었습니다.", data={"type": "auth_approved"})


async def reject_capture(
    capture_id: int,
    admin: AdminUser,
    reason: str,
    db: AsyncSession,
) -> None:
    """관리자 거절 → user.auth_pending = False, S3 파일 삭제."""
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

    if user:
        user.auth_pending = False

    db.add(AdminAction(
        admin_id=admin.id,
        action_type="reject_capture",
        target_type="capture",
        target_id=capture.id,
        detail=reason,
    ))
    await db.commit()

    _delete_s3_object(capture.s3_key)

    if user and user.fcm_token:
        await send_push(
            user.fcm_token,
            title="가입 심사 결과",
            body=f"심사가 반려되었습니다. 사유: {reason[:60]}",
            data={"type": "auth_rejected"},
        )


async def list_pending_captures(db: AsyncSession) -> list[AuthCapture]:
    result = await db.execute(
        select(AuthCapture).where(AuthCapture.status == "pending").order_by(AuthCapture.created_at.asc())
    )
    return result.scalars().all()
