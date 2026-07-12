from datetime import datetime
from typing import Optional
from pydantic import BaseModel, field_validator


class ChildProfile(BaseModel):
    id: int
    school_code: Optional[str] = None
    school_name: Optional[str] = None
    grade: Optional[int] = None
    class_num: Optional[int] = None
    school_type: Optional[str] = None
    region: Optional[str] = None
    # 학원 추천용 — 가입 시엔 선택 입력, 학원 검색 시 필수로 요구됨(프론트에서 게이팅)
    learning_goals: Optional[list[str]] = None

    model_config = {"from_attributes": True}


class LearningGoalsUpdate(BaseModel):
    learning_goals: list[str]

    @field_validator("learning_goals")
    @classmethod
    def check_not_empty(cls, v: list[str]) -> list[str]:
        if not v:
            raise ValueError("학습 목표를 1개 이상 선택해주세요.")
        return v


class UserProfile(BaseModel):
    id: int
    nickname: Optional[str] = None
    region: Optional[str] = None
    school_name: Optional[str] = None
    grade: Optional[int] = None
    school_type: Optional[str] = None
    manner_score: int
    temperature: float = 36.5
    member_grade: str = "lurker"
    auth_pending: bool = False
    is_admin: bool = False
    is_trusted: bool = False
    admin_username: Optional[str] = None
    reject_reason: Optional[str] = None
    profile_updated_at: Optional[datetime] = None
    created_at: datetime
    children: list[ChildProfile] = []
    active_child_id: Optional[int] = None
    academy_review_count: int = 0
    learning_goals: Optional[list[str]] = None

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


class AddChildRequest(BaseModel):
    school_code: str
    school_name: str
    grade: int
    class_num: Optional[int] = None
    school_type: str
    region: Optional[str] = None

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
