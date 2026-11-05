from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, JSONType, UTCDateTime, in_check, utcnow
from app.models.enums import DecisionSource, DecisionStatus, DecisionType


class DeliveryDecision(Base):
    __tablename__ = "delivery_decisions"
    __table_args__ = (
        sa.CheckConstraint(in_check("decision_type", DecisionType), name="decision_type_valid"),
        sa.CheckConstraint(
            in_check("decision_status", DecisionStatus), name="decision_status_valid"
        ),
        sa.CheckConstraint(
            in_check("decision_source", DecisionSource), name="decision_source_valid"
        ),
        sa.CheckConstraint(
            "confidence IS NULL OR (confidence BETWEEN 0 AND 1)", name="confidence_range"
        ),
        sa.Index("ix_delivery_decisions_delivery_id", "delivery_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    delivery_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("deliveries.id", ondelete="CASCADE"), nullable=False
    )
    decision_type: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    automated_result: Mapped[str | None] = mapped_column(sa.String(40))
    final_result: Mapped[str | None] = mapped_column(sa.String(40))
    confidence: Mapped[float | None] = mapped_column(sa.Numeric(4, 3, asdecimal=False))
    decision_status: Mapped[str] = mapped_column(
        sa.String(30),
        nullable=False,
        default=DecisionStatus.REVIEW_RECOMMENDED.value,
        server_default="REVIEW_RECOMMENDED",
    )
    decision_source: Mapped[str] = mapped_column(
        sa.String(30),
        nullable=False,
        default=DecisionSource.AI_ASSIST.value,
        server_default="AI_ASSIST",
    )
    evidence: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, onupdate=utcnow
    )
