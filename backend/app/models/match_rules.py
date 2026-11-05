from __future__ import annotations

import uuid

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _flag(default: bool) -> Mapped[bool]:
    return mapped_column(
        sa.Boolean,
        nullable=False,
        default=default,
        server_default=sa.true() if default else sa.false(),
    )


class MatchRules(Base):
    """Per-match umpiring rules. One row per match."""

    __tablename__ = "match_rules"
    __table_args__ = (
        sa.CheckConstraint(
            "max_bouncers_per_over IS NULL OR (max_bouncers_per_over BETWEEN 0 AND 6)",
            name="max_bouncers_range",
        ),
        sa.CheckConstraint(
            "lateral_reach_multiplier BETWEEN 0.20 AND 1.50", name="lateral_reach_range"
        ),
    )

    match_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("matches.id", ondelete="CASCADE"), primary_key=True
    )
    wide_enabled: Mapped[bool] = _flag(True)
    no_ball_enabled: Mapped[bool] = _flag(True)
    front_foot_no_ball_enabled: Mapped[bool] = _flag(False)
    edge_review_enabled: Mapped[bool] = _flag(True)
    lbw_review_enabled: Mapped[bool] = _flag(True)
    full_toss_above_waist_is_no_ball: Mapped[bool] = _flag(True)
    bounced_above_shoulder_is_no_ball: Mapped[bool] = _flag(False)
    max_bouncers_per_over: Mapped[int | None] = mapped_column(sa.SmallInteger)
    lateral_reach_multiplier: Mapped[float] = mapped_column(
        sa.Numeric(4, 2, asdecimal=False), nullable=False, default=0.60, server_default="0.60"
    )
