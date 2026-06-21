"""Firebase Cloud Messaging 발송 헬퍼.

FCM_SERVICE_ACCOUNT_JSON 환경변수가 없으면 발송을 조용히 건너뜀.
firebase-admin 패키지가 없어도 ImportError 없이 동작 (graceful degradation).
"""
import json
import logging
from typing import Optional

logger = logging.getLogger(__name__)

_app = None
_init_tried = False


def _init() -> bool:
    global _app, _init_tried
    if _init_tried:
        return _app is not None
    _init_tried = True

    from app.core.config import settings
    if not settings.FCM_SERVICE_ACCOUNT_JSON:
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials

        cred_dict = json.loads(settings.FCM_SERVICE_ACCOUNT_JSON)
        cred = credentials.Certificate(cred_dict)
        _app = firebase_admin.initialize_app(cred)
        logger.info("FCM initialized")
        return True
    except Exception as exc:
        logger.warning("FCM init skipped: %s", exc)
        return False


async def send_push(
    token: Optional[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> None:
    """FCM 단일 기기 푸시. 실패해도 예외 전파하지 않음."""
    if not token or not _init():
        return
    try:
        from firebase_admin import messaging

        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=token,
        )
        messaging.send(msg, app=_app)
    except Exception as exc:
        logger.warning("FCM send failed (token=%s...): %s", token[:10], exc)
