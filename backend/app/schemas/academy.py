from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator


class AcademyResponse(BaseModel):
    id: int
    neis_academy_code: Optional[str] = None
    name: str
    region: Optional[str] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    subjects: Optional[list[str]] = None
    school_type: Optional[str] = None
    is_b2b: bool = False

    @field_validator("is_b2b", mode="before")
    @classmethod
    def coerce_is_b2b(cls, v: object) -> bool:
        return bool(v) if v is not None else False
    review_count: int = 0
    avg_rating: Optional[float] = None

    model_config = {"from_attributes": True}


class AcademyReviewCreate(BaseModel):
    rating: int
    subjects: Optional[list[str]] = None       # 다중 과목
    teacher_styles: Optional[list[str]] = None  # 다중 선생님 스타일 (최대 3)
    homework_level: Optional[str] = None
    score_improvement: Optional[str] = None
    review_text: str
    nickname_type: str = "anon"
    is_anonymous: bool = True

    @field_validator("rating")
    @classmethod
    def check_rating(cls, v: int) -> int:
        if not (1 <= v <= 5):
            raise ValueError("별점은 1~5 사이여야 합니다.")
        return v

    @field_validator("review_text")
    @classmethod
    def check_text(cls, v: str) -> str:
        if len(v.strip()) < 10:
            raise ValueError("후기는 10자 이상 입력해주세요.")
        return v.strip()

    @field_validator("teacher_styles")
    @classmethod
    def check_teacher_styles(cls, v: Optional[list[str]]) -> Optional[list[str]]:
        if v and len(v) > 3:
            raise ValueError("선생님 스타일은 최대 3개까지 선택할 수 있습니다.")
        return v


class AcademyReviewResponse(BaseModel):
    id: int
    academy_id: int
    subjects: Optional[list[str]] = None
    teacher_styles: Optional[list[str]] = None
    homework_level: Optional[str] = None
    score_improvement: Optional[str] = None
    review_text: str
    rating: int
    nickname_type: str = "anon"
    is_anonymous: bool = True
    is_seed: bool = False
    author_display_name: Optional[str] = None
    author_school_name: Optional[str] = None
    author_grade: Optional[int] = None
    report_count: int = 0
    is_hidden: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}


class QuotaInfo(BaseModel):
    visible: int
    total: int
    can_unlock_more: bool
    next_unlock_at: int  # 다음 해금까지 필요한 후기 수


class AcademyReviewListResponse(BaseModel):
    reviews: list[AcademyReviewResponse]
    quota_info: QuotaInfo
