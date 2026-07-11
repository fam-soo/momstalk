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
    review_count: int = 0          # 전체 (seed 포함, DB 원본)
    user_review_count: int = 0     # 사용자 후기만 (seed 제외)
    has_seed: bool = False         # AI 요약 정보(seed) 보유 여부
    avg_rating: Optional[float] = None
    is_unlocked: bool = False      # 로그인한 유저가 이 학원 후기를 이미 열람(해금)했는지 여부

    model_config = {"from_attributes": True, "populate_by_name": True}


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


class AcademyReviewUpdate(AcademyReviewCreate):
    pass


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
    is_view_limited: bool = False  # True이면 텍스트/상세 내용이 제거된 잠금 상태
    is_own: bool = False  # 로그인한 유저 본인이 작성한 후기인지 여부
    author_display_name: Optional[str] = None
    author_school_name: Optional[str] = None
    author_grade: Optional[int] = None
    report_count: int = 0
    is_hidden: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}


class QuotaInfo(BaseModel):
    total: int                      # 이 학원의 전체 후기 수 (사용자 후기, seed 제외)
    academy_locked: bool            # True면 이 학원의 후기 전체(기본 소개 + 사용자 후기)가 가림 처리됨
    unlocked_academy_count: int     # 현재까지 가림 처리 없이 열람 가능하도록 해금한 학원 수
    unlocked_academy_limit: Optional[int] = None  # 해금 가능한 학원 총 개수 (None=무제한)
    next_unlock_at: int             # 다음 해금까지 필요한 후기 작성 수 (0이면 이미 무제한)
    user_review_count: int          # 유저가 작성한 후기 수


class AcademyReviewListResponse(BaseModel):
    reviews: list[AcademyReviewResponse]
    quota_info: QuotaInfo


class AcademyUnlockQuota(BaseModel):
    """후기 게시판 상단 배너용 — 특정 학원과 무관한 전역 해금 현황."""
    unlocked_academy_count: int
    unlocked_academy_limit: Optional[int] = None
    next_unlock_at: int
    user_review_count: int
