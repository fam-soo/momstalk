import hashlib
import hmac
from datetime import datetime, timedelta

from jose import jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(subject: str) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return jwt.encode({"sub": subject, "exp": expire}, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(subject: str) -> str:
    expire = datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    return jwt.encode({"sub": subject, "exp": expire, "type": "refresh"}, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])


def make_anon_id(phone_number: str) -> str:
    """
    전화번호 → 복호화 불가능한 익명 ID 생성.
    ANON_HASH_SECRET으로 HMAC-SHA256 처리하여 서비스 DB에서 신원 역추적 불가.
    같은 전화번호는 항상 같은 anon_id를 생성 (1인 1계정 보장).
    """
    return hmac.new(
        settings.ANON_HASH_SECRET.encode(),
        phone_number.encode(),
        hashlib.sha256,
    ).hexdigest()
