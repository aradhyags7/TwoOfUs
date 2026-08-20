from typing import Optional, List
from pydantic import BaseModel

class MessageCreate(BaseModel):
    sender_id: int
    receiver_id: int
    content: str
    nonce: Optional[str] = None
    is_encrypted: Optional[bool] = False
    media_ids: Optional[List[int]] = []

class EditMessageRequest(BaseModel):
    content: str
    nonce: Optional[str] = None
    is_encrypted: Optional[bool] = False