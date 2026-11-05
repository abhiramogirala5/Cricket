from __future__ import annotations

import uuid

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, in_check
from app.models.enums import BattingHand


class MatchPlayer(Base):
    """A player's place in one match. Natural key ``(match_id, player_id)``."""

    __tablename__ = "match_players"
    __table_args__ = (
        sa.CheckConstraint(in_check("batting_hand", BattingHand), name="batting_hand_valid"),
        sa.CheckConstraint(
            "declared_height_cm IS NULL OR (declared_height_cm BETWEEN 100 AND 230)",
            name="declared_height_range",
        ),
        sa.CheckConstraint(
            "batting_order IS NULL OR (batting_order BETWEEN 1 AND 30)", name="batting_order_range"
        ),
        sa.Index("ix_match_players_player_id", "player_id"),
    )

    match_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("matches.id", ondelete="CASCADE"), primary_key=True
    )
    player_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("players.id"), primary_key=True
    )
    team_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, sa.ForeignKey("teams.id"), nullable=False)
    batting_hand: Mapped[str] = mapped_column(
        sa.String(10), nullable=False, default=BattingHand.UNKNOWN.value, server_default="UNKNOWN"
    )
    declared_height_cm: Mapped[int | None] = mapped_column(sa.SmallInteger)
    batting_order: Mapped[int | None] = mapped_column(sa.SmallInteger)
    is_captain: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )
    is_wicketkeeper: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )
