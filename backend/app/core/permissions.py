"""
회원 등급 기반 FastAPI 의존성.

member_grade:
  lurker  — 가입 완료 전 또는 심사 중 (읽기 전용)
  member  — 정회원 (쓰기 가능)
"""
from fastapi import Depends, HTTPException, status

from app.api.deps import get_current_user
from app.models.service_models import User


async def require_member(user: User = Depends(get_current_user)) -> User:
    """정회원만 통과. 눈팅 회원은 403."""
    if user.member_grade != "member":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="정회원만 이용할 수 있는 기능입니다. 학교 인증을 완료해 주세요.",
        )
    return user


async def require_lurker_or_member(user: User = Depends(get_current_user)) -> User:
    """눈팅 회원 이상 통과 (로그인만 되면 됨). 사실상 get_current_user와 동일하나 명시적으로 사용."""
    return user
