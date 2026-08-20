from typing import Optional
from sqlalchemy import Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base


class Pair(Base):
    __tablename__ = "pairs"

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        index=True
    )

    user1_id: Mapped[int] = mapped_column(
        Integer,
        nullable=False
    )

    user2_id: Mapped[int] = mapped_column(
        Integer,
        nullable=False
    )

    connection_pin: Mapped[Optional[str]] = mapped_column(
        String,
        unique=True
    )