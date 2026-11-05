from __future__ import annotations

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, UTCDateTime


class SyncEvent(Base):
    """Idempotency ledger. Only APPLIED events are recorded (see API_CONTRACT §5.2)."""

    __tablename__ = "sync_events"

    owner_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    event_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    entity_type: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    action: Mapped[str] = mapped_column(sa.String(10), nullable=False)
    applied_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
