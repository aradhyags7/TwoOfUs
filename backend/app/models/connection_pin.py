from typing import Optional
from sqlalchemy import Integer, String
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