from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import Integer, String, Text, DateTime
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base


class DiaryMemory(Base):
    __tablename__ = "diary_memories"

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        index=True
    )

    sender_id: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        index=True
    )

    receiver_id: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        index=True
    )

    entry_date: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        index=True
    )

    content: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        default=""
    )

    mood_emoji: Mapped[Optional[str]] = mapped_column(
        String(10),
        nullable=True
    )

    image_url: Mapped[Optional[str]] = mapped_column(
        String(500),
        nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc)
    )
