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
    # 강남엄마 스크래핑으로 보강된 필드 — DB 모델엔 있었지만 이 스키마에 빠져 있어
    # API 응답에서 계속 잘려나가던 버그가 있었다(화면에 절대 안 뜨는 원인이었음)
    avg_class_capacity: Optional[float] = None
    avg_tuition_10k_won: Optional[float] = None
    business_hours: Optional[str] = None
    shuttle_bus: Optional[bool] = None
    curriculum_focus: Optional[list[str]] = None
    class_style: Optional[list[str]] = None
    facilities: Optional[list[str]] = None

    model_config = {"from_attributes": True, "populate_by_name": True}


class AcademyReviewCreate(BaseModel):
    rating: int
    subjects: Optional[list[str]] = None       # 다중 과목
    teacher_styles: Optional[list[str]] = None  # 다중 선생님 스타일 (최대 3)
    homework_level: Optional[str] = None
    score_improvement: Optional[str] = None
    # 학원 추천 매칭용 — 후기 작성 시점 기준 수강생 성향/성적대
    student_traits: Optional[list[str]] = None
    score_level: Optional[str] = None
    feedback_frequency: Optional[str] = None  # 일간|주간|월간|분기|반기
    score_change: Optional[dict] = None       # {"before": "...", "after": "..."}
    recommend_to_similar: Optional[bool] = None
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
    student_traits: Optional[list[str]] = None
    score_level: Optional[str] = None
    feedback_frequency: Optional[str] = None
    score_change: Optional[dict] = None
    recommend_to_similar: Optional[bool] = None
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


class AcademyInfoUpdate(BaseModel):
    """후기 작성 시점에 사용자가 확인/수정하는 학원 기본 정보(선택 입력).
    보낸 필드만 반영 — 값을 지우고 싶으면 빈 문자열/빈 배열 등 명시적으로 보내야 한다."""
    subjects: Optional[list[str]] = None
    business_hours: Optional[str] = None
    shuttle_bus: Optional[bool] = None
    avg_class_capacity: Optional[float] = None
    avg_tuition_10k_won: Optional[float] = None
    facilities: Optional[list[str]] = None


class RecommendationRequest(BaseModel):
    """학원 추천받기 5단계 설문."""
    subjects: list[str]                              # 1단계 (필수, 1개 이상)
    subject_levels: dict[str, dict[str, str]] = {}    # 2단계 — {"수학": {"수준": "...", "성적": "..."}}
    homework_tolerance: Optional[str] = None          # 3단계 — "30분"|"60분"|"90분"|"120분"|"상관없음"
    management_need: Optional[str] = None             # 3단계 — "자기주도형"|"가끔관리필요"|"밀착관리필요"
    desired_style: Optional[str] = None                # 3단계 — "자유로운 분위기"|"적당한 관리"|"철저한 관리"
    goals: list[str] = []                              # 4단계 (최대 3)
    constraints: list[str] = []                        # 4단계 (최대 3)
    learning_goals: list[str] = []                      # 학습 목표 (선행/심화/내신/수능/경시/영재)
    note: Optional[str] = None                          # 5단계 (선택, 저장 안 함 — 표시만)
    region: Optional[str] = None                        # 레거시 단일 지역 (regions 없을 때 fallback)
    regions: list[str] = []                             # 검색 대상 지역 (기본 지역 + 추가 선택, 복수)
    child_id: int                                       # 추천 대상 자녀 (필수 — 학교급 필터링에 사용)

    @field_validator("subjects")
    @classmethod
    def check_subjects(cls, v: list[str]) -> list[str]:
        if not v:
            raise ValueError("과목을 1개 이상 선택해주세요.")
        return v


class AcademyMatchResult(BaseModel):
    academy: AcademyResponse
    match_score: int                    # 0~100
    match_reasons: list[str] = []       # 매칭 근거 짧은 설명


class RecommendationResponse(BaseModel):
    results: list[AcademyMatchResult]
    # True면 조건에 딱 맞는 학원이 없어서, 과목만 일치하는 학원을 평점순으로
    # 대신 보여주는 상태 — match_score는 참고용 순위일 뿐 실제 매칭도가 아님
    is_fallback: bool = False
