from typing import Optional
from datetime import datetime
from sqlalchemy import Integer, String, DateTime, Boolean
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base


class ConnectionPin(Base):
    __tablename__ = "connection_pins"

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        index=True
    )

    user_id: Mapped[int] = mapped_column(
        Integer,
        nullable=False
    )

    pin_code: Mapped[Optional[str]] = mapped_column(
        String,
        unique=True
    )

    created_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime,
        nullable=True
    )

    expires_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime,
        nullable=True
    )

    is_consumed: Mapped[bool] = mapped_column(
        Boolean,
        default=False
    )
