from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class MediaResponse(BaseModel):
    id: int
    message_id: Optional[int] = None
    sender_id: int
    receiver_id: int
    original_filename: str
    stored_filename: str
    media_type: str
    mime_type: str
    file_size: int
    storage_path: str
    thumbnail_path: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    duration_seconds: Optional[float] = None
    created_at: Optional[datetime] = None
    is_encrypted: Optional[bool] = False
    is_view_once: Optional[bool] = False
    is_expired: Optional[bool] = False
    viewed_at: Optional[datetime] = None
    encrypted_media_key: Optional[str] = None
    encryption_nonce: Optional[str] = None

    class Config:
        from_attributes = True


class MediaUploadResponse(BaseModel):
    media_id: int
    original_filename: str
    stored_filename: str
    media_type: str
    mime_type: str
    file_size: int
    storage_path: str
    thumbnail_path: Optional[str] = None
    is_view_once: Optional[bool] = False
