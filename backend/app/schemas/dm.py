from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class ConversationResponse(BaseModel):
    id: int
    other_user_id: int
    other_nickname: str
    last_message: Optional[str] = None
    last_message_at: Optional[datetime] = None
    unread_count: int = 0

    model_config = {"from_attributes": True}


class MessageCreate(BaseModel):
    content: str


class MessageResponse(BaseModel):
    id: int
    conversation_id: int
    sender_id: int
    content: str
    is_read: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class BlockResponse(BaseModel):
    blocked_user_id: int
    created_at: datetime

    model_config = {"from_attributes": True}
