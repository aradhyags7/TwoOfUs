from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, DateTime
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String, unique=True, index=True, nullable=False)
    username: Mapped[str] = mapped_column(String, unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String, nullable=False)

    bio: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    avatar_url: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    birthday: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    public_key: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    reset_otp: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    reset_otp_expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)