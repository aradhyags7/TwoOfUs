from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base

class CallSession(Base):
    __tablename__ = "call_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    caller_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"))
    receiver_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"))
    call_type: Mapped[str] = mapped_column(String, default="voice")  # "voice" | "video"
    status: Mapped[str] = mapped_column(String, default="ringing")  # "ringing" | "ongoing" | "ended" | "rejected" | "missed"
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    duration_seconds: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
