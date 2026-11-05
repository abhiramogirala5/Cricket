from __future__ import annotations

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, UTCDateTime, in_check, utcnow
from app.models.enums import MatchStatus


class Match(Base):
    __tablename__ = "matches"
    __table_args__ = (
        sa.CheckConstraint("team_a_id <> team_b_id", name="teams_differ"),
        sa.CheckConstraint(in_check("status", MatchStatus), name="status_valid"),
        sa.CheckConstraint("overs_per_innings BETWEEN 1 AND 50", name="overs_range"),
        sa.Index("ix_matches_owner_id_created_at", "owner_id", "created_at"),
        sa.Index("ix_matches_status", "status"),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    owner_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    team_a_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, sa.ForeignKey("teams.id"), nullable=False)
    team_b_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, sa.ForeignKey("teams.id"), nullable=False)
    match_name: Mapped[str | None] = mapped_column(sa.String(150))
    location_name: Mapped[str | None] = mapped_column(sa.String(255))
    scheduled_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    started_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    status: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default=MatchStatus.DRAFT.value, server_default="DRAFT"
    )
    overs_per_innings: Mapped[int] = mapped_column(
        sa.SmallInteger, nullable=False, default=6, server_default="6"
    )
    local_rules_profile: Mapped[str] = mapped_column(
        sa.String(40), nullable=False, default="CASUAL_GULLY", server_default="CASUAL_GULLY"
    )
    winner_team_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("teams.id"))
    result_summary: Mapped[str | None] = mapped_column(sa.String(255))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, onupdate=utcnow
    )
