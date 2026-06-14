from datetime import datetime
from pydantic import BaseModel


class UserProfile(BaseModel):
    id: int
    nickname: str
    school_name: str
    grade: int
    class_num: int
    school_type: str
    manner_score: int
    created_at: datetime

    model_config = {"from_attributes": True}


class UpdateNicknameRequest(BaseModel):
    nickname: str

    def model_post_init(self, __context) -> None:
        if len(self.nickname) < 2 or len(self.nickname) > 20:
            raise ValueError("닉네임은 2~20자 사이여야 합니다.")
