from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, JSONType, UTCDateTime, in_check, utcnow
from app.models.enums import WicketFamily


def _confidence() -> Mapped[float]:
    return mapped_column(sa.Numeric(4, 3, asdecimal=False), nullable=False)


class WicketDetection(Base):
    __tablename__ = "wicket_detections"
    __table_args__ = (
        sa.CheckConstraint(in_check("wicket_family", WicketFamily), name="wicket_family_valid"),
        sa.CheckConstraint("object_confidence BETWEEN 0 AND 1", name="object_confidence_range"),
        sa.CheckConstraint("temporal_stability BETWEEN 0 AND 1", name="temporal_stability_range"),
        sa.CheckConstraint("context_confidence BETWEEN 0 AND 1", name="context_confidence_range"),
        sa.CheckConstraint("final_confidence BETWEEN 0 AND 1", name="final_confidence_range"),
        sa.Index("ix_wicket_detections_match_id_is_active", "match_id", "is_active"),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    match_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("matches.id", ondelete="CASCADE"), nullable=False
    )
    scene_scan_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("scene_scans.id", ondelete="SET NULL")
    )
    wicket_family: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    bounding_box: Mapped[dict[str, Any]] = mapped_column(JSONType, nullable=False)
    target_polygon: Mapped[list[Any]] = mapped_column(JSONType, nullable=False)
    target_plane: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    ground_contact_line: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    object_confidence: Mapped[float] = _confidence()
    temporal_stability: Mapped[float] = _confidence()
    context_confidence: Mapped[float] = _confidence()
    final_confidence: Mapped[float] = _confidence()
    is_active: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=True, server_default=sa.true()
    )
    model_version: Mapped[str] = mapped_column(sa.String(100), nullable=False)
    detected_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utcnow)
