from datetime import datetime
from typing import Any, Dict, Optional
from pydantic import BaseModel

class CallInitiateRequest(BaseModel):
    receiver_id: int
    call_type: str = "voice"  # "voice" | "video"

class CallRespondRequest(BaseModel):
    call_id: int
    action: str  # "accept" | "reject"

class CallEndRequest(BaseModel):
    call_id: int

class CallSignalRequest(BaseModel):
    call_id: int
    target_user_id: int
    signal_type: str  # "offer" | "answer" | "ice_candidate"
    payload: Dict[str, Any]

class CallSessionResponse(BaseModel):
    id: int
    caller_id: int
    receiver_id: int
    call_type: str
    status: str
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    duration_seconds: int = 0
    created_at: datetime

    class Config:
        from_attributes = True
