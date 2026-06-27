"""
SMS 인증 서비스.
SMS_API_KEY가 설정되어 있으면 실제 CoolSMS로 발송,
없으면 개발 모드로 콘솔에 코드를 출력한다.
"""
import random
import string
from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.config import settings
from app.core.security import create_access_token, decode_token
from app.models.service_models import PhoneVerification


def _generate_code(length: int = 6) -> str:
    return "".join(random.choices(string.digits, k=length))


async def send_verification_code(phone_number: str, db: AsyncSession) -> None:
    code = _generate_code()
    expires_at = datetime.utcnow() + timedelta(minutes=5)

    # 기존 미사용 코드 무효화
    existing = await db.execute(
        select(PhoneVerification)
        .where(PhoneVerification.phone_number == phone_number)
        .where(PhoneVerification.is_used == False)
    )
    for row in existing.scalars().all():
        row.is_used = True

    db.add(PhoneVerification(
        phone_number=phone_number,
        code=code,
        expires_at=expires_at,
    ))
    await db.commit()

    if settings.SMS_API_KEY:
        # 실제 CoolSMS 연동 (프로덕션)
        _send_via_coolsms(phone_number, code)
    else:
        # 개발 모드 — 콘솔 출력
        print(f"\n[DEV] SMS 인증코드 → {phone_number} : {code}\n")


def _send_via_coolsms(phone_number: str, code: str) -> None:
    """CoolSMS REST API 연동 — 프로덕션에서 사용."""
    import httpx
    import hmac
    import hashlib
    import time
    import uuid

    timestamp = str(int(time.time() * 1000))
    salt = str(uuid.uuid4()).replace("-", "")
    signature = hmac.new(
        settings.SMS_API_SECRET.encode(),
        f"{timestamp}{salt}".encode(),
        hashlib.sha256,
    ).hexdigest()

    httpx.post(
        "https://api.coolsms.co.kr/messages/v4/send",
        headers={
            "Authorization": f"HMAC-SHA256 apiKey={settings.SMS_API_KEY}, date={timestamp}, salt={salt}, signature={signature}",
        },
        json={
            "message": {
                "to": phone_number,
                "from": settings.SMS_SENDER,
                "text": f"[MomsTalk] 인증번호 [{code}]를 입력해주세요. (5분 이내)",
            }
        },
        timeout=10,
    )


async def verify_code_and_get_token(phone_number: str, code: str, db: AsyncSession) -> str:
    """코드 검증 후 단기 SMS 토큰 반환 (학부모 인증 단계에서 소비)."""
    result = await db.execute(
        select(PhoneVerification)
        .where(PhoneVerification.phone_number == phone_number)
        .where(PhoneVerification.code == code)
        .where(PhoneVerification.is_used == False)
        .where(PhoneVerification.expires_at > datetime.utcnow())
        .order_by(PhoneVerification.created_at.desc())
        .limit(1)
    )
    record = result.scalar_one_or_none()

    if not record:
        raise ValueError("인증코드가 올바르지 않거나 만료되었습니다.")

    record.is_used = True
    await db.commit()

    # phone_number를 subject로 한 단기 토큰 (10분)
    return create_access_token(f"sms:{phone_number}")


async def decode_sms_token(sms_token: str) -> str:
    """SMS 토큰에서 전화번호 추출."""
    try:
        payload = decode_token(sms_token)
        sub: str = payload.get("sub", "")
        if not sub.startswith("sms:"):
            raise ValueError()
        return sub[4:]
    except Exception:
        raise ValueError("SMS 토큰이 유효하지 않습니다.")
