"""
인증 DB 전용 모델 (AUTH_DATABASE_URL 연결)
서비스 DB와 물리적으로 분리하여 신원 역추적 불가능하게 함.
"""
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, Integer, String
from sqlalchemy.orm import DeclarativeBase


class AuthBase(DeclarativeBase):
    pass


class PhoneVerification(AuthBase):
    """SMS 인증 코드 임시 저장 (TTL 5분)"""
    __tablename__ = "phone_verifications"

    id = Column(Integer, primary_key=True)
    phone_number = Column(String(20), nullable=False, index=True)
    code = Column(String(6), nullable=False)
    is_used = Column(Boolean, default=False)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class ParentVerification(AuthBase):
    """
    학부모 인증 레코드.
    anon_id = HMAC-SHA256(전화번호, ANON_HASH_SECRET) — 서비스 DB의 User와는 이 값만 공유.
    이 테이블에서 anon_id로 phone_number를 역산하는 것은 불가능.
    """
    __tablename__ = "parent_verifications"

    id = Column(Integer, primary_key=True)
    anon_id = Column(String(64), unique=True, nullable=False, index=True)
    school_code = Column(String(20), nullable=False)   # NEIS 학교 코드
    school_name = Column(String(100), nullable=False)
    grade = Column(Integer, nullable=False)             # 1~6 (초), 1~3 (중/고)
    class_num = Column(Integer, nullable=False)
    school_type = Column(String(10), nullable=False)    # elementary / middle / high
    verified_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)
