"""
하위 호환 모듈. 인증 모델은 service_models로 통합되었습니다.
기존 import 경로(app.models.auth_models)를 유지하기 위한 re-export.
"""
from app.models.service_models import Base as AuthBase, PhoneVerification, ParentVerification

__all__ = ["AuthBase", "PhoneVerification", "ParentVerification"]
