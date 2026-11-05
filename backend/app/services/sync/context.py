"""Context passed to every sync handler plus owner-scoped lookup helpers."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.delivery import Delivery
from app.models.innings import Innings
from app.models.match import Match
from app.models.player import Player
from app.models.team import Team
from app.services.sync.errors import FORBIDDEN, PARENT_NOT_FOUND, SyncRejection


@dataclass(frozen=True, slots=True)
class SyncContext:
    session: AsyncSession
    owner_id: uuid.UUID
    now: datetime

    def ensure_owner(self, row_owner_id: uuid.UUID, what: str) -> None:
        """Reject writes to something that belongs to another user."""
        if row_owner_id != self.owner_id:
            raise SyncRejection(FORBIDDEN, f"{what} belongs to another user")


async def require_owned_match(ctx: SyncContext, match_id: uuid.UUID) -> Match:
    match = await ctx.session.get(Match, match_id)
    if match is None:
        raise SyncRejection(PARENT_NOT_FOUND, "the match does not exist")
    ctx.ensure_owner(match.owner_id, "the match")
    return match


async def require_owned_player(ctx: SyncContext, player_id: uuid.UUID) -> Player:
    player = await ctx.session.get(Player, player_id)
    if player is None:
        raise SyncRejection(PARENT_NOT_FOUND, "the player does not exist")
    ctx.ensure_owner(player.owner_id, "the player")
    return player


async def require_owned_team(ctx: SyncContext, team_id: uuid.UUID) -> Team:
    team = await ctx.session.get(Team, team_id)
    if team is None:
        raise SyncRejection(PARENT_NOT_FOUND, "the team does not exist")
    ctx.ensure_owner(team.owner_id, "the team")
    return team


async def require_owned_innings(
    ctx: SyncContext, innings_id: uuid.UUID, *, lock: bool = False
) -> tuple[Innings, Match]:
    """Load an innings with its match, checking ownership.

    ``lock=True`` takes ``SELECT … FOR UPDATE`` on the innings row (PostgreSQL) so concurrent
    batches cannot interleave delivery sequence numbers; it also refreshes the loaded state.
    """
    stmt = (
        select(Innings, Match)
        .join(Match, Match.id == Innings.match_id)
        .where(Innings.id == innings_id)
    )
    if lock:
        stmt = stmt.with_for_update(of=Innings).execution_options(populate_existing=True)
    row = (await ctx.session.execute(stmt)).one_or_none()
    if row is None:
        raise SyncRejection(PARENT_NOT_FOUND, "the innings does not exist")
    innings, match = row
    ctx.ensure_owner(match.owner_id, "the innings")
    return innings, match


async def require_owned_delivery(ctx: SyncContext, delivery_id: uuid.UUID) -> Delivery:
    stmt = (
        select(Delivery, Match.owner_id)
        .join(Innings, Innings.id == Delivery.innings_id)
        .join(Match, Match.id == Innings.match_id)
        .where(Delivery.id == delivery_id)
    )
    row = (await ctx.session.execute(stmt)).one_or_none()
    if row is None:
        raise SyncRejection(PARENT_NOT_FOUND, "the delivery does not exist")
    delivery, owner_id = row
    ctx.ensure_owner(owner_id, "the delivery")
    return delivery
