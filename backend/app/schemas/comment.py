from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class CommentCreate(BaseModel):
    content: str
    parent_id: Optional[int] = None   # 대댓글이면 부모 댓글 ID
    is_anonymous: bool = True

    def model_post_init(self, __context) -> None:
        if len(self.content) < 1:
            raise ValueError("댓글 내용을 입력해주세요.")


class CommentResponse(BaseModel):
    id: int
    post_id: int
    parent_id: Optional[int]
    content: str
    is_anonymous: bool
    like_count: int
    is_hidden: bool
    is_post_author: bool = False     # 댓글 작성자 == 게시글 작성자 여부 → '작성자' 뱃지
    is_liked: bool = False           # 현재 유저의 좋아요 여부
    created_at: datetime
    author_nickname: Optional[str] = None  # is_anonymous=True이면 None

    model_config = {"from_attributes": True}


class ReportRequest(BaseModel):
    target_type: str   # post / comment
    target_id: int
    reason: str

    def model_post_init(self, __context) -> None:
        if self.target_type not in ("post", "comment"):
            raise ValueError("target_type은 post 또는 comment여야 합니다.")
