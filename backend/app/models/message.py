from typing import Optional, List
from sqlalchemy import Integer, Text, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime, timezone

from ..core.database import Base


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        index=True
    )

    sender_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id")
    )

    receiver_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id")
    )

    content: Mapped[str] = mapped_column(Text)

    nonce: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    is_encrypted: Mapped[bool] = mapped_column(
        Boolean,
        default=False
    )

    is_edited: Mapped[bool] = mapped_column(
        Boolean,
        default=False
    )

    created_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc)
    )

    media_attachments = relationship("Media", back_populates="message", cascade="all, delete-orphan")