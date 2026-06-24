from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class PostCreate(BaseModel):
    board_type: str       # grade / school / free / region
    title: str
    content: str
    is_anonymous: bool = True
    mention_tags: list[str] = []  # free 게시판 전용: ["region:기장군", "school:B100", "grade:1"]

    def model_post_init(self, __context) -> None:
        if self.board_type not in ("grade", "school", "free", "region"):
            raise ValueError("board_type은 grade / school / free / region 중 하나여야 합니다.")
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
    is_liked: bool = False               # 현재 유저의 좋아요 여부
    is_scraped: bool = False             # 현재 유저의 스크랩 여부
    is_mine: bool = False                # 현재 유저가 작성한 글인지 (익명 포함)

    model_config = {"from_attributes": True}


class PostListItem(BaseModel):
    id: int
    board_type: str
    title: str
    is_anonymous: bool
    view_count: int
    like_count: int
    scrap_count: int
    comment_count: int = 0
    mention_tags: list[str] = []
    is_liked: bool = False
    is_pinned: bool = False  # 현재 유저와 @태그가 매칭되는 경우 True
    is_hot: bool = False     # 인기글 여부
    created_at: datetime

    model_config = {"from_attributes": True}


class ScrapResponse(BaseModel):
    id: int
    title: str
    board_type: str
    like_count: int
    scrap_count: int
    created_at: datetime

    model_config = {"from_attributes": True}
