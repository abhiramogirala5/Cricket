from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, JSONType, UTCDateTime, utcnow


class SceneScan(Base):
    __tablename__ = "scene_scans"
    __table_args__ = (
        sa.CheckConstraint("overall_confidence BETWEEN 0 AND 1", name="overall_confidence_range"),
        sa.CheckConstraint(
            "capture_fps IS NULL OR (capture_fps BETWEEN 1 AND 240)", name="capture_fps_range"
        ),
        sa.CheckConstraint("scan_duration_ms >= 0", name="scan_duration_non_negative"),
        sa.Index("ix_scene_scans_match_id", "match_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    match_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("matches.id", ondelete="CASCADE"), nullable=False
    )
    camera_device_model: Mapped[str | None] = mapped_column(sa.String(150))
    capture_fps: Mapped[int | None] = mapped_column(sa.SmallInteger)
    scan_duration_ms: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    ground_plane: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    pitch_direction: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    batsman_plane: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    overall_confidence: Mapped[float] = mapped_column(
        sa.Numeric(4, 3, asdecimal=False), nullable=False
    )
    model_version: Mapped[str] = mapped_column(sa.String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utcnow)
