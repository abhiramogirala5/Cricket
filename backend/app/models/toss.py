from __future__ import annotations

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, UTCDateTime, in_check, utcnow
from app.models.enums import TossDecision, TossSide


class Toss(Base):
    __tablename__ = "tosses"
    __table_args__ = (
        sa.UniqueConstraint("match_id"),
        sa.CheckConstraint(in_check("call_choice", TossSide), name="call_choice_valid"),
        sa.CheckConstraint(in_check("result", TossSide), name="result_valid"),
        sa.CheckConstraint(
            "winner_decision IS NULL OR " + in_check("winner_decision", TossDecision),
            name="winner_decision_valid",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    match_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("matches.id", ondelete="CASCADE"), nullable=False
    )
    called_by_player_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("players.id")
    )
    call_choice: Mapped[str] = mapped_column(sa.String(10), nullable=False)
    result: Mapped[str] = mapped_column(sa.String(10), nullable=False)
    winner_team_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("teams.id"))
    winner_decision: Mapped[str | None] = mapped_column(sa.String(10))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utcnow)
