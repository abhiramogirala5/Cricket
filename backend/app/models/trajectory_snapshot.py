from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, JSONType, UTCDateTime, utcnow


class TrajectorySnapshot(Base):
    __tablename__ = "trajectory_snapshots"
    __table_args__ = (
        sa.CheckConstraint("sampling_fps BETWEEN 1 AND 240", name="sampling_fps_range"),
        sa.Index("ix_trajectory_snapshots_delivery_id", "delivery_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    delivery_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("deliveries.id", ondelete="CASCADE"), nullable=False
    )
    sampling_fps: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False)
    points_compressed: Mapped[list[Any]] = mapped_column(JSONType, nullable=False)
    model_version: Mapped[str] = mapped_column(sa.String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utcnow)
