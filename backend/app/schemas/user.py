from datetime import datetime
from typing import Optional
from pydantic import BaseModel, field_validator


class UserProfile(BaseModel):
    id: int
    nickname: str
    certified_nickname: Optional[str] = None
    region: Optional[str] = None
    school_name: str
    grade: int
    school_type: str
    manner_score: int
    temperature: float = 36.5    # manner_score → °C (API 계산값)
    member_grade: str = "lurker"
    auth_pending: bool = False
    is_admin: bool = False
    reject_reason: Optional[str] = None
    profile_updated_at: Optional[datetime] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class UpdateNicknameRequest(BaseModel):
    nickname: str

    def model_post_init(self, __context) -> None:
        if len(self.nickname) < 2 or len(self.nickname) > 20:
            raise ValueError("닉네임은 2~20자 사이여야 합니다.")


class UpdateProfileRequest(BaseModel):
    region: str
    school_code: str
    school_name: str
    grade: int
    school_type: str

    @field_validator("grade")
    @classmethod
    def check_grade(cls, v: int) -> int:
        if not (1 <= v <= 6):
            raise ValueError("학년은 1~6 사이여야 합니다.")
        return v

    @field_validator("school_type")
    @classmethod
    def check_school_type(cls, v: str) -> str:
        if v not in ("elementary", "middle", "high"):
            raise ValueError("school_type은 elementary / middle / high 중 하나여야 합니다.")
        return v
