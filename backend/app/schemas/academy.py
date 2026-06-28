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
    review_count: int = 0
    avg_rating: Optional[float] = None

    model_config = {"from_attributes": True}


class AcademyReviewCreate(BaseModel):
    rating: int
    subject: Optional[str] = None
    teacher_style: Optional[str] = None
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


class AcademyReviewResponse(BaseModel):
    id: int
    academy_id: int
    subject: Optional[str] = None
    teacher_style: Optional[str] = None
    homework_level: Optional[str] = None
    score_improvement: Optional[str] = None
    review_text: str
    rating: int
    nickname_type: str = "anon"
    is_anonymous: bool = True
    author_display_name: Optional[str] = None
    author_school_name: Optional[str] = None
    author_grade: Optional[int] = None
    report_count: int = 0
    is_hidden: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}
