"""공통 FastAPI 의존성."""
from datetime import datetime, timezone
from typing import Optional
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.security import decode_token
from app.db import get_db
from app.models.service_models import User

bearer_scheme = HTTPBearer()
optional_bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    token = credentials.credentials
    try:
        payload = decode_token(token)
        user_id: str = payload.get("sub")
        if not user_id or payload.get("type") == "refresh":
            raise ValueError()
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="유효하지 않은 토큰입니다.",
        )

    result = await db.execute(select(User).where(User.id == int(user_id)))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="존재하지 않는 계정입니다.")

    if user.is_banned:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="영구 정지된 계정입니다.")

    if user.suspended_until:
        now = datetime.now(timezone.utc).replace(tzinfo=None)  # DB는 naive UTC
        if user.suspended_until > now:
            until_str = user.suspended_until.strftime("%Y-%m-%d %H:%M") + " (UTC)"
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"계정이 정지되었습니다. 해제 시각: {until_str}",
                headers={"X-Suspend-Until": user.suspended_until.isoformat()},
            )

    return user


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(optional_bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Optional[User]:
    """인증 선택적 dependency — 토큰 없으면 None 반환."""
    if not credentials:
        return None
    try:
        payload = decode_token(credentials.credentials)
        user_id: str = payload.get("sub")
        if not user_id or payload.get("type") == "refresh":
            return None
    except Exception:
        return None

    result = await db.execute(select(User).where(User.id == int(user_id)))
    user = result.scalar_one_or_none()
    if not user or user.is_banned:
        return None
    return user
