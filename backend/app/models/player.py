from __future__ import annotations

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, UTCDateTime, in_check, utcnow
from app.models.enums import BattingHand


class Player(Base):
    """A roster entry owned by a user. Players do not need an account."""

    __tablename__ = "players"
    __table_args__ = (
        sa.CheckConstraint(in_check("batting_hand", BattingHand), name="batting_hand_valid"),
        sa.CheckConstraint(
            "declared_height_cm IS NULL OR (declared_height_cm BETWEEN 100 AND 230)",
            name="declared_height_range",
        ),
        sa.Index("ix_players_owner_id", "owner_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    owner_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    display_name: Mapped[str] = mapped_column(sa.String(100), nullable=False)
    batting_hand: Mapped[str] = mapped_column(
        sa.String(10), nullable=False, default=BattingHand.UNKNOWN.value, server_default="UNKNOWN"
    )
    declared_height_cm: Mapped[int | None] = mapped_column(sa.SmallInteger)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, onupdate=utcnow
    )
