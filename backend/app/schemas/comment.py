from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class CommentCreate(BaseModel):
    content: str
    parent_id: Optional[int] = None   # 대댓글이면 부모 댓글 ID
    is_anonymous: bool = True
    nickname_type: str = "anon"       # anon / certified

    def model_post_init(self, __context) -> None:
        if len(self.content) < 1:
            raise ValueError("댓글 내용을 입력해주세요.")
        if self.nickname_type not in ("anon", "certified"):
            raise ValueError("nickname_type은 anon / certified 중 하나여야 합니다.")
        if self.nickname_type == "certified":
            self.is_anonymous = False


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
    is_mine: bool = False            # 현재 조회 유저가 작성한 댓글
    nickname_type: str = "anon"
    anon_label: Optional[str] = None   # 익명 표시명: "글쓴이" / "익명1" / "익명2" ... (is_anonymous=True일 때만)
    created_at: datetime
    author_nickname: Optional[str] = None    # nickname_type=anon이면 익명닉네임, certified이면 인증닉네임

    model_config = {"from_attributes": True}


REPORT_CATEGORIES = {
    "SPAM": "스팸/홍보",
    "OBSCENE": "음란/선정적 내용",
    "ABUSE": "욕설/비방/혐오",
    "PERSONAL_INFO": "개인정보 노출",
    "MISINFORMATION": "허위 사실/명예훼손",
    "ILLEGAL": "불법 정보 (마약/도박 등)",
    "OFF_TOPIC": "주제와 무관한 게시물",
    "OTHER": "기타",
}


class ReportRequest(BaseModel):
    target_type: str   # post / comment
    target_id: int
    category: str = "OTHER"   # REPORT_CATEGORIES 키 중 하나
    reason: str = ""          # 기타 사유 직접 입력 (category=OTHER이면 필수)

    def model_post_init(self, __context) -> None:
        if self.target_type not in ("post", "comment"):
            raise ValueError("target_type은 post 또는 comment여야 합니다.")
        if self.category not in REPORT_CATEGORIES:
            raise ValueError(f"category는 {list(REPORT_CATEGORIES.keys())} 중 하나여야 합니다.")
        if self.category == "OTHER" and not self.reason.strip():
            raise ValueError("기타 신고 사유를 입력해주세요.")
