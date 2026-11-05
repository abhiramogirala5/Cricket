from __future__ import annotations

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, UTCDateTime


class Innings(Base):
    """One innings. ``total_runs``, ``wickets`` and ``legal_balls`` are server-computed."""

    __tablename__ = "innings"
    __table_args__ = (
        sa.UniqueConstraint("match_id", "innings_number"),
        sa.CheckConstraint("batting_team_id <> bowling_team_id", name="teams_differ"),
        sa.CheckConstraint("innings_number BETWEEN 1 AND 4", name="innings_number_range"),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    match_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("matches.id", ondelete="CASCADE"), nullable=False
    )
    innings_number: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False)
    batting_team_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("teams.id"), nullable=False
    )
    bowling_team_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("teams.id"), nullable=False
    )
    total_runs: Mapped[int] = mapped_column(
        sa.Integer, nullable=False, default=0, server_default="0"
    )
    wickets: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0, server_default="0")
    legal_balls: Mapped[int] = mapped_column(
        sa.Integer, nullable=False, default=0, server_default="0"
    )
    started_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
