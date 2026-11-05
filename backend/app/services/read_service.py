"""Owner-scoped read queries (API_CONTRACT §4). Every query is filtered by ``owner_id``."""

from __future__ import annotations

import uuid
from collections import defaultdict

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import not_found
from app.models.delivery import Delivery
from app.models.delivery_decision import DeliveryDecision
from app.models.enums import MatchStatus
from app.models.innings import Innings
from app.models.match import Match
from app.models.match_player import MatchPlayer
from app.models.match_rules import MatchRules
from app.models.player import Player
from app.models.scene_scan import SceneScan
from app.models.team import Team
from app.models.toss import Toss
from app.models.trajectory_snapshot import TrajectorySnapshot
from app.models.wicket_detection import WicketDetection
from app.schemas.common import Page
from app.schemas.read import (
    DeliveryDecisionRead,
    DeliveryRead,
    InningsBrief,
    InningsRead,
    MatchPlayerRead,
    MatchRead,
    MatchRulesRead,
    MatchSnapshot,
    MatchSummary,
    PlayerRead,
    SceneScanRead,
    TeamBrief,
    TeamRead,
    TossRead,
    TrajectorySnapshotRead,
    WicketDetectionRead,
)


async def list_players(
    session: AsyncSession, owner_id: uuid.UUID, *, limit: int, offset: int
) -> Page[PlayerRead]:
    total = await session.scalar(
        select(func.count()).select_from(Player).where(Player.owner_id == owner_id)
    )
    rows = await session.scalars(
        select(Player)
        .where(Player.owner_id == owner_id)
        .order_by(Player.display_name, Player.id)
        .limit(limit)
        .offset(offset)
    )
    return Page[PlayerRead](
        items=[PlayerRead.model_validate(row) for row in rows],
        total=total or 0,
        limit=limit,
        offset=offset,
    )


async def list_teams(
    session: AsyncSession, owner_id: uuid.UUID, *, limit: int, offset: int
) -> Page[TeamRead]:
    total = await session.scalar(
        select(func.count()).select_from(Team).where(Team.owner_id == owner_id)
    )
    rows = await session.scalars(
        select(Team)
        .where(Team.owner_id == owner_id)
        .order_by(Team.name, Team.id)
        .limit(limit)
        .offset(offset)
    )
    return Page[TeamRead](
        items=[TeamRead.model_validate(row) for row in rows],
        total=total or 0,
        limit=limit,
        offset=offset,
    )


async def list_matches(
    session: AsyncSession,
    owner_id: uuid.UUID,
    *,
    status: MatchStatus | None,
    limit: int,
    offset: int,
) -> Page[MatchSummary]:
    conditions = [Match.owner_id == owner_id]
    if status is not None:
        conditions.append(Match.status == status.value)

    total = await session.scalar(select(func.count()).select_from(Match).where(*conditions))
    matches = list(
        await session.scalars(
            select(Match)
            .where(*conditions)
            .order_by(Match.created_at.desc(), Match.id)
            .limit(limit)
            .offset(offset)
        )
    )
    if not matches:
        return Page[MatchSummary](items=[], total=total or 0, limit=limit, offset=offset)

    team_ids = {m.team_a_id for m in matches} | {m.team_b_id for m in matches}
    teams = {
        team.id: team
        for team in await session.scalars(
            select(Team).where(Team.owner_id == owner_id, Team.id.in_(team_ids))
        )
    }
    innings_by_match: dict[uuid.UUID, list[Innings]] = defaultdict(list)
    for innings in await session.scalars(
        select(Innings)
        .where(Innings.match_id.in_([m.id for m in matches]))
        .order_by(Innings.innings_number)
    ):
        innings_by_match[innings.match_id].append(innings)

    items = [
        MatchSummary(
            id=m.id,
            match_name=m.match_name,
            location_name=m.location_name,
            status=MatchStatus(m.status),
            overs_per_innings=m.overs_per_innings,
            team_a=TeamBrief.model_validate(teams[m.team_a_id]),
            team_b=TeamBrief.model_validate(teams[m.team_b_id]),
            started_at=m.started_at,
            completed_at=m.completed_at,
            winner_team_id=m.winner_team_id,
            result_summary=m.result_summary,
            innings=[InningsBrief.model_validate(i) for i in innings_by_match.get(m.id, [])],
            created_at=m.created_at,
            updated_at=m.updated_at,
        )
        for m in matches
    ]
    return Page[MatchSummary](items=items, total=total or 0, limit=limit, offset=offset)


async def get_match_snapshot(
    session: AsyncSession, owner_id: uuid.UUID, match_id: uuid.UUID
) -> MatchSnapshot:
    match = await session.scalar(
        select(Match).where(Match.id == match_id, Match.owner_id == owner_id)
    )
    if match is None:
        raise not_found("Match not found.")

    rules = await session.get(MatchRules, match_id)
    teams = list(
        await session.scalars(
            select(Team)
            .where(Team.owner_id == owner_id, Team.id.in_([match.team_a_id, match.team_b_id]))
            .order_by(Team.name, Team.id)
        )
    )
    match_players = list(
        await session.scalars(
            select(MatchPlayer)
            .where(MatchPlayer.match_id == match_id)
            .order_by(MatchPlayer.team_id, MatchPlayer.batting_order, MatchPlayer.player_id)
        )
    )
    player_ids = {mp.player_id for mp in match_players}
    players = (
        list(
            await session.scalars(
                select(Player)
                .where(Player.owner_id == owner_id, Player.id.in_(player_ids))
                .order_by(Player.display_name, Player.id)
            )
        )
        if player_ids
        else []
    )
    toss = await session.scalar(select(Toss).where(Toss.match_id == match_id))
    innings = list(
        await session.scalars(
            select(Innings).where(Innings.match_id == match_id).order_by(Innings.innings_number)
        )
    )
    innings_ids = select(Innings.id).where(Innings.match_id == match_id)
    deliveries = list(
        await session.scalars(
            select(Delivery)
            .where(Delivery.innings_id.in_(innings_ids))
            .order_by(Delivery.innings_id, Delivery.delivery_sequence)
        )
    )
    delivery_ids = select(Delivery.id).where(Delivery.innings_id.in_(innings_ids))
    decisions = list(
        await session.scalars(
            select(DeliveryDecision)
            .where(DeliveryDecision.delivery_id.in_(delivery_ids))
            .order_by(DeliveryDecision.created_at, DeliveryDecision.id)
        )
    )
    trajectories = list(
        await session.scalars(
            select(TrajectorySnapshot)
            .where(TrajectorySnapshot.delivery_id.in_(delivery_ids))
            .order_by(TrajectorySnapshot.created_at, TrajectorySnapshot.id)
        )
    )
    scans = list(
        await session.scalars(
            select(SceneScan)
            .where(SceneScan.match_id == match_id)
            .order_by(SceneScan.created_at, SceneScan.id)
        )
    )
    detections = list(
        await session.scalars(
            select(WicketDetection)
            .where(WicketDetection.match_id == match_id)
            .order_by(WicketDetection.detected_at, WicketDetection.id)
        )
    )

    return MatchSnapshot(
        match=MatchRead.model_validate(match),
        rules=MatchRulesRead.model_validate(rules) if rules is not None else None,
        teams=[TeamRead.model_validate(t) for t in teams],
        players=[PlayerRead.model_validate(p) for p in players],
        match_players=[MatchPlayerRead.model_validate(mp) for mp in match_players],
        toss=TossRead.model_validate(toss) if toss is not None else None,
        innings=[InningsRead.model_validate(i) for i in innings],
        deliveries=[DeliveryRead.model_validate(d) for d in deliveries],
        delivery_decisions=[DeliveryDecisionRead.model_validate(d) for d in decisions],
        scene_scans=[SceneScanRead.model_validate(s) for s in scans],
        wicket_detections=[WicketDetectionRead.model_validate(w) for w in detections],
        trajectory_snapshots=[TrajectorySnapshotRead.model_validate(t) for t in trajectories],
    )
