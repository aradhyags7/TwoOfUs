from typing import Optional
from pydantic import BaseModel


class MemoryCreateRequest(BaseModel):
    partner_id: int
    entry_date: str
    content: str
    mood_emoji: Optional[str] = None


class MemoryResponse(BaseModel):
    id: int
    sender_id: int
    receiver_id: int
    entry_date: str
    content: str
    mood_emoji: Optional[str] = None
    image_url: Optional[str] = None
    created_at: str

    class Config:
        from_attributes = True
