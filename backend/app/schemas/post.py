from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class PostCreate(BaseModel):
    board_type: str       # grade / school / free / region
    title: str
    content: str
    is_anonymous: bool = False
    nickname_type: str = "anon"   # anon / certified
    mention_tags: list[str] = []  # free 게시판 전용: ["region:기장군", "school:B100", "grade:1"]
    # 관리자 전용: 특정 지역/학교를 타겟으로 공지 작성 시 사용
    target_region: Optional[str] = None
    target_school_code: Optional[str] = None

    def model_post_init(self, __context) -> None:
        if self.board_type not in ("grade", "school", "free", "region", "notice"):
            raise ValueError("board_type은 grade / school / free / region / notice 중 하나여야 합니다.")
        if self.nickname_type not in ("anon", "certified"):
            raise ValueError("nickname_type은 anon / certified 중 하나여야 합니다.")
        if self.nickname_type == "certified":
            self.is_anonymous = False
        if len(self.title) < 2 or len(self.title) > 200:
            raise ValueError("제목은 2~200자 사이여야 합니다.")
        if len(self.content) < 5:
            raise ValueError("내용은 5자 이상이어야 합니다.")


class PostUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None


class PostAuthor(BaseModel):
    nickname: str
    manner_score: int

    model_config = {"from_attributes": True}


class PostResponse(BaseModel):
    id: int
    board_type: str
    title: str
    content: str
    is_anonymous: bool
    nickname_type: str = "anon"
    author_display_name: Optional[str] = None   # 표시용 닉네임 (익명이면 None)
    author_badge: Optional[str] = None   # "미취학" / "2학년" 등 — 작성자 자녀 상태 뱃지
    view_count: int
    like_count: int
    scrap_count: int
    report_count: int
    is_hidden: bool
    comment_count: int = 0
    mention_tags: list[str] = []
    created_at: datetime
    updated_at: datetime
    author: Optional[PostAuthor] = None  # is_anonymous=True이면 None
    is_liked: bool = False
    is_scraped: bool = False
    is_mine: bool = False

    model_config = {"from_attributes": True}


class PostListItem(BaseModel):
    id: int
    board_type: str
    title: str
    is_anonymous: bool
    nickname_type: str = "anon"
    author_display_name: Optional[str] = None
    author_badge: Optional[str] = None   # "미취학" / "2학년" 등 — 작성자 자녀 상태 뱃지
    author_region: Optional[str] = None    # 관리자용: 작성자 지역
    author_school: Optional[str] = None    # 관리자용: 작성자 학교명
    view_count: int
    like_count: int
    scrap_count: int
    comment_count: int = 0
    mention_tags: list[str] = []
    is_liked: bool = False
    is_pinned: bool = False
    is_notice: bool = False
    is_hot: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}


class PostListResponse(BaseModel):
    """cursor 기반 무한 스크롤 응답."""
    items: list[PostListItem]
    next_cursor: Optional[int] = None   # 다음 페이지 커서 (마지막 post.id), None이면 끝


class ScrapResponse(BaseModel):
    id: int
    title: str
    board_type: str
    like_count: int
    scrap_count: int
    created_at: datetime

    model_config = {"from_attributes": True}
