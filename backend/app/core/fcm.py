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
        # 이 로그가 없으면 "푸시가 전혀 안 온다"는 신고를 받아도 원인(설정 누락 vs
        # 발송 실패 vs 토큰 없음)을 서버 로그만으로 구분할 방법이 없었다.
        logger.warning("FCM 비활성화: FCM_SERVICE_ACCOUNT_JSON 환경변수가 설정되지 않음 — 모든 푸시 발송이 조용히 스킵됨")
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials

        cred_dict = json.loads(settings.FCM_SERVICE_ACCOUNT_JSON)
        cred = credentials.Certificate(cred_dict)
        _app = firebase_admin.initialize_app(cred)
        logger.info("FCM initialized (project=%s)", cred_dict.get("project_id"))
        return True
    except Exception as exc:
        logger.warning("FCM init 실패: %s", exc)
        return False


async def send_push(
    token: Optional[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> None:
    """FCM 단일 기기 푸시. 실패해도 예외 전파하지 않음."""
    if not token:
        logger.info("FCM 발송 스킵: 수신자 fcm_token 없음 (title=%r)", title)
        return
    if not _init():
        return  # _init()이 이미 원인을 로그로 남김
    try:
        from firebase_admin import messaging

        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=token,
        )
        message_id = messaging.send(msg, app=_app)
        logger.info("FCM 발송 성공: id=%s title=%r token=%s...", message_id, title, token[:12])
    except Exception as exc:
        logger.warning("FCM 발송 실패 (token=%s...): %s", token[:12], exc)
