from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.database import Base


class Media(Base):
    __tablename__ = "media"

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        index=True
    )

    message_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("messages.id", ondelete="CASCADE"),
        nullable=True,
        index=True
    )

    sender_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id"),
        nullable=False,
        index=True
    )

    receiver_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id"),
        nullable=False,
        index=True
    )

    pair_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("pairs.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )

    original_filename: Mapped[str] = mapped_column(String, nullable=False)
    stored_filename: Mapped[str] = mapped_column(String, nullable=False)
    media_type: Mapped[str] = mapped_column(String, nullable=False)  # "image", "video", "file"
    mime_type: Mapped[str] = mapped_column(String, nullable=False)
    file_size: Mapped[int] = mapped_column(Integer, nullable=False)  # bytes

    storage_path: Mapped[str] = mapped_column(String, nullable=False)
    thumbnail_path: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    width: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    height: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    duration_seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    created_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc)
    )

    # Future E2EE fields
    is_encrypted: Mapped[bool] = mapped_column(Boolean, default=False)
    is_view_once: Mapped[bool] = mapped_column(Boolean, default=False)
    is_expired: Mapped[bool] = mapped_column(Boolean, default=False)
    viewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    encrypted_media_key: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    ciphertext_hash: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    encryption_nonce: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    encryption_version: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    message = relationship("Message", back_populates="media_attachments")
