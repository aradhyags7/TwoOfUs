from datetime import datetime
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field

class CallInitiateRequest(BaseModel):
    receiver_id: int
    call_type: str = "voice"  # "voice" | "video"

class CallRespondRequest(BaseModel):
    call_id: int
    action: str  # "accept" | "reject"
    reason: Optional[str] = None

class CallEndRequest(BaseModel):
    call_id: int
    reason: Optional[str] = "normal_hangup"

class CallSignalRequest(BaseModel):
    call_id: int
    target_user_id: int
    signal_type: str  # "offer" | "answer" | "ice_candidate"
    payload: Dict[str, Any]

class SignalingMessage(BaseModel):
    version: str = "1.0"
    call_id: Optional[int] = None
    type: str
    sender_id: Optional[int] = None
    target_id: Optional[int] = None
    timestamp: Optional[str] = None
    payload: Dict[str, Any] = Field(default_factory=dict)

class DevicePushTokenRequest(BaseModel):
    token: str
    platform: str = "android"  # "android" | "ios"

class TurnCredentialsResponse(BaseModel):
    username: str
    password: str
    ttl: int
    uris: List[str]

class CallSessionResponse(BaseModel):
    id: int
    caller_id: int
    receiver_id: int
    call_type: str
    status: str
    rejection_reason: Optional[str] = None
    ended_reason: Optional[str] = None
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    duration_seconds: int = 0
    created_at: datetime

    class Config:
        from_attributes = True
