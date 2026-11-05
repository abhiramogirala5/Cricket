from __future__ import annotations

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, UTCDateTime, in_check, utcnow
from app.models.enums import DismissalType

_CONFIDENCE_COLUMNS = (
    "speed_confidence",
    "ball_tracking_confidence",
    "pose_tracking_confidence",
    "wicket_tracking_confidence",
)


def _opt_confidence() -> Mapped[float | None]:
    return mapped_column(sa.Numeric(4, 3, asdecimal=False))


def _flag() -> Mapped[bool]:
    return mapped_column(sa.Boolean, nullable=False, default=False, server_default=sa.false())


class Delivery(Base):
    """One ball. Voided deliveries are kept (``is_voided``) and excluded from aggregates."""

    __tablename__ = "deliveries"
    __table_args__ = (
        sa.UniqueConstraint("innings_id", "delivery_sequence"),
        sa.CheckConstraint("runs_bat BETWEEN 0 AND 7", name="runs_bat_range"),
        sa.CheckConstraint("runs_extras BETWEEN 0 AND 10", name="runs_extras_range"),
        sa.CheckConstraint(
            "legal_ball_number IS NULL OR (legal_ball_number BETWEEN 1 AND 6)",
            name="legal_ball_number_range",
        ),
        sa.CheckConstraint(
            "dismissal_type IS NULL OR " + in_check("dismissal_type", DismissalType),
            name="dismissal_type_valid",
        ),
        *(
            sa.CheckConstraint(
                f"{column} IS NULL OR ({column} BETWEEN 0 AND 1)", name=f"{column}_range"
            )
            for column in _CONFIDENCE_COLUMNS
        ),
        sa.Index(
            "ix_deliveries_innings_id_over_number_delivery_sequence",
            "innings_id",
            "over_number",
            "delivery_sequence",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    innings_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("innings.id", ondelete="CASCADE"), nullable=False
    )
    wicket_detection_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("wicket_detections.id", ondelete="SET NULL")
    )
    delivery_sequence: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    over_number: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False)
    legal_ball_number: Mapped[int | None] = mapped_column(sa.SmallInteger)
    bowler_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("players.id"), nullable=False
    )
    striker_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("players.id"), nullable=False
    )
    non_striker_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("players.id"))
    dismissed_player_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("players.id")
    )
    runs_bat: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False, default=0)
    runs_extras: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False, default=0)
    is_wide: Mapped[bool] = _flag()
    is_no_ball: Mapped[bool] = _flag()
    is_bye: Mapped[bool] = _flag()
    is_leg_bye: Mapped[bool] = _flag()
    is_wicket: Mapped[bool] = _flag()
    dismissal_type: Mapped[str | None] = mapped_column(sa.String(20))
    speed_kmph: Mapped[float | None] = mapped_column(sa.Numeric(6, 2, asdecimal=False))
    speed_confidence: Mapped[float | None] = _opt_confidence()
    ball_tracking_confidence: Mapped[float | None] = _opt_confidence()
    pose_tracking_confidence: Mapped[float | None] = _opt_confidence()
    wicket_tracking_confidence: Mapped[float | None] = _opt_confidence()
    is_voided: Mapped[bool] = _flag()
    voided_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    void_reason: Mapped[str | None] = mapped_column(sa.String(100))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utcnow)
