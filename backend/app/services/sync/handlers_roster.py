"""Sync handlers for players, teams, matches and match setup (API_CONTRACT §5.3)."""

from __future__ import annotations

from sqlalchemy import delete, select

from app.models.enums import MatchStatus
from app.models.innings import Innings
from app.models.match import Match
from app.models.match_player import MatchPlayer
from app.models.match_rules import MatchRules
from app.models.player import Player
from app.models.scene_scan import SceneScan
from app.models.team import Team
from app.models.toss import Toss
from app.models.wicket_detection import WicketDetection
from app.schemas.sync import (
    InningsPayload,
    MatchDeletePayload,
    MatchPayload,
    MatchPlayerPayload,
    MatchRulesPayload,
    PlayerPayload,
    SceneScanPayload,
    TeamPayload,
    TossPayload,
    WicketDetectionPayload,
)
from app.services.sync.context import (
    SyncContext,
    require_owned_match,
    require_owned_player,
    require_owned_team,
)
from app.services.sync.errors import (
    INVALID_REFERENCE,
    INVALID_STATE,
    PARENT_NOT_FOUND,
    SyncRejection,
)


async def upsert_player(ctx: SyncContext, p: PlayerPayload) -> None:
    row = await ctx.session.get(Player, p.id)
    if row is None:
        ctx.session.add(
            Player(
                id=p.id,
                owner_id=ctx.owner_id,
                display_name=p.display_name,
                batting_hand=p.batting_hand.value,
                declared_height_cm=p.declared_height_cm,
                created_at=ctx.now,
                updated_at=ctx.now,
            )
        )
        return
    ctx.ensure_owner(row.owner_id, "the player")
    row.display_name = p.display_name
    row.batting_hand = p.batting_hand.value
    row.declared_height_cm = p.declared_height_cm
    row.updated_at = ctx.now


async def upsert_team(ctx: SyncContext, p: TeamPayload) -> None:
    row = await ctx.session.get(Team, p.id)
    if row is None:
        ctx.session.add(
            Team(
                id=p.id, owner_id=ctx.owner_id, name=p.name, created_at=ctx.now, updated_at=ctx.now
            )
        )
        return
    ctx.ensure_owner(row.owner_id, "the team")
    row.name = p.name
    row.updated_at = ctx.now


async def upsert_match(ctx: SyncContext, p: MatchPayload) -> None:
    existing = await ctx.session.get(Match, p.id)
    if existing is not None:
        ctx.ensure_owner(existing.owner_id, "the match")
    await require_owned_team(ctx, p.team_a_id)
    await require_owned_team(ctx, p.team_b_id)
    if p.winner_team_id is not None and p.winner_team_id not in (p.team_a_id, p.team_b_id):
        raise SyncRejection(INVALID_REFERENCE, "winner_team_id must be one of the match teams")

    if existing is None:
        ctx.session.add(
            Match(
                id=p.id,
                owner_id=ctx.owner_id,
                team_a_id=p.team_a_id,
                team_b_id=p.team_b_id,
                match_name=p.match_name,
                location_name=p.location_name,
                scheduled_at=p.scheduled_at,
                started_at=p.started_at,
                completed_at=p.completed_at,
                status=p.status.value,
                overs_per_innings=p.overs_per_innings,
                local_rules_profile=p.local_rules_profile,
                winner_team_id=p.winner_team_id,
                result_summary=p.result_summary,
                created_at=ctx.now,
                updated_at=ctx.now,
            )
        )
        return

    if (existing.team_a_id, existing.team_b_id) != (p.team_a_id, p.team_b_id):
        raise SyncRejection(INVALID_STATE, "the teams of a match cannot be changed")
    current = MatchStatus(existing.status)
    if current.is_terminal and p.status != current:
        raise SyncRejection(
            INVALID_STATE, f"a {current.value} match cannot change status to {p.status.value}"
        )
    existing.match_name = p.match_name
    existing.location_name = p.location_name
    existing.scheduled_at = p.scheduled_at
    existing.started_at = p.started_at
    existing.completed_at = p.completed_at
    existing.status = p.status.value
    existing.overs_per_innings = p.overs_per_innings
    existing.local_rules_profile = p.local_rules_profile
    existing.winner_team_id = p.winner_team_id
    existing.result_summary = p.result_summary
    existing.updated_at = ctx.now


async def delete_match(ctx: SyncContext, p: MatchDeletePayload) -> None:
    row = await ctx.session.get(Match, p.id)
    if row is None:
        return  # idempotent
    ctx.ensure_owner(row.owner_id, "the match")
    await ctx.session.execute(delete(Match).where(Match.id == p.id))
    # Children are removed by database cascades; drop every cached instance so later events in
    # the same batch cannot see deleted rows through the identity map.
    ctx.session.expunge_all()


async def upsert_match_player(ctx: SyncContext, p: MatchPlayerPayload) -> None:
    match = await require_owned_match(ctx, p.match_id)
    await require_owned_player(ctx, p.player_id)
    if p.team_id not in (match.team_a_id, match.team_b_id):
        raise SyncRejection(INVALID_REFERENCE, "team_id must be one of the match teams")
    row = await ctx.session.get(MatchPlayer, (p.match_id, p.player_id))
    if row is None:
        ctx.session.add(
            MatchPlayer(
                match_id=p.match_id,
                player_id=p.player_id,
                team_id=p.team_id,
                batting_hand=p.batting_hand.value,
                declared_height_cm=p.declared_height_cm,
                batting_order=p.batting_order,
                is_captain=p.is_captain,
                is_wicketkeeper=p.is_wicketkeeper,
            )
        )
        return
    row.team_id = p.team_id
    row.batting_hand = p.batting_hand.value
    row.declared_height_cm = p.declared_height_cm
    row.batting_order = p.batting_order
    row.is_captain = p.is_captain
    row.is_wicketkeeper = p.is_wicketkeeper


async def upsert_match_rules(ctx: SyncContext, p: MatchRulesPayload) -> None:
    await require_owned_match(ctx, p.match_id)
    values = p.model_dump()
    row = await ctx.session.get(MatchRules, p.match_id)
    if row is None:
        ctx.session.add(MatchRules(**values))
        return
    for name, value in values.items():
        if name != "match_id":
            setattr(row, name, value)


async def upsert_scene_scan(ctx: SyncContext, p: SceneScanPayload) -> None:
    await require_owned_match(ctx, p.match_id)
    row = await ctx.session.get(SceneScan, p.id)
    if row is not None and row.match_id != p.match_id:
        raise SyncRejection(INVALID_STATE, "a scene scan cannot move to another match")
    if row is None:
        row = SceneScan(id=p.id, match_id=p.match_id, created_at=p.created_at or ctx.now)
        ctx.session.add(row)
    elif p.created_at is not None:
        row.created_at = p.created_at
    row.camera_device_model = p.camera_device_model
    row.capture_fps = p.capture_fps
    row.scan_duration_ms = p.scan_duration_ms
    row.ground_plane = p.ground_plane
    row.pitch_direction = p.pitch_direction
    row.batsman_plane = p.batsman_plane
    row.overall_confidence = p.overall_confidence
    row.model_version = p.model_version


async def upsert_wicket_detection(ctx: SyncContext, p: WicketDetectionPayload) -> None:
    await require_owned_match(ctx, p.match_id)
    if p.scene_scan_id is not None:
        scan = await ctx.session.get(SceneScan, p.scene_scan_id)
        if scan is None:
            raise SyncRejection(PARENT_NOT_FOUND, "the scene scan does not exist")
        if scan.match_id != p.match_id:
            raise SyncRejection(INVALID_REFERENCE, "the scene scan belongs to another match")
    row = await ctx.session.get(WicketDetection, p.id)
    if row is not None and row.match_id != p.match_id:
        raise SyncRejection(INVALID_STATE, "a wicket detection cannot move to another match")
    if row is None:
        row = WicketDetection(id=p.id, match_id=p.match_id, detected_at=p.detected_at or ctx.now)
        ctx.session.add(row)
    elif p.detected_at is not None:
        row.detected_at = p.detected_at
    row.scene_scan_id = p.scene_scan_id
    row.wicket_family = p.wicket_family.value
    row.bounding_box = p.bounding_box.model_dump()
    row.target_polygon = [point.model_dump() for point in p.target_polygon]
    row.target_plane = p.target_plane
    row.ground_contact_line = p.ground_contact_line
    row.object_confidence = p.object_confidence
    row.temporal_stability = p.temporal_stability
    row.context_confidence = p.context_confidence
    row.final_confidence = p.final_confidence
    row.is_active = p.is_active
    row.model_version = p.model_version


async def upsert_toss(ctx: SyncContext, p: TossPayload) -> None:
    match = await require_owned_match(ctx, p.match_id)
    by_id = await ctx.session.get(Toss, p.id)
    if by_id is not None and by_id.match_id != p.match_id:
        raise SyncRejection(INVALID_STATE, "a toss cannot move to another match")
    for_match = await ctx.session.scalar(select(Toss).where(Toss.match_id == p.match_id))
    if for_match is not None and for_match.id != p.id:
        raise SyncRejection(INVALID_STATE, "this match already has a toss")
    if p.called_by_player_id is not None:
        member = await ctx.session.get(MatchPlayer, (p.match_id, p.called_by_player_id))
        if member is None:
            raise SyncRejection(
                INVALID_REFERENCE, "called_by_player_id is not a player of this match"
            )
    if p.winner_team_id is not None and p.winner_team_id not in (match.team_a_id, match.team_b_id):
        raise SyncRejection(INVALID_REFERENCE, "winner_team_id must be one of the match teams")

    row = by_id
    if row is None:
        row = Toss(id=p.id, match_id=p.match_id, created_at=ctx.now)
        ctx.session.add(row)
    row.called_by_player_id = p.called_by_player_id
    row.call_choice = p.call_choice.value
    row.result = p.result.value
    row.winner_team_id = p.winner_team_id
    row.winner_decision = p.winner_decision.value if p.winner_decision else None


async def upsert_innings(ctx: SyncContext, p: InningsPayload) -> None:
    match = await require_owned_match(ctx, p.match_id)
    teams = (match.team_a_id, match.team_b_id)
    if p.batting_team_id not in teams or p.bowling_team_id not in teams:
        raise SyncRejection(INVALID_REFERENCE, "batting and bowling teams must be the match teams")
    row = await ctx.session.get(Innings, p.id)
    if row is None:
        clash = await ctx.session.scalar(
            select(Innings.id).where(
                Innings.match_id == p.match_id, Innings.innings_number == p.innings_number
            )
        )
        if clash is not None:
            raise SyncRejection(
                INVALID_STATE, f"innings number {p.innings_number} already exists for this match"
            )
        ctx.session.add(
            Innings(
                id=p.id,
                match_id=p.match_id,
                innings_number=p.innings_number,
                batting_team_id=p.batting_team_id,
                bowling_team_id=p.bowling_team_id,
                started_at=p.started_at,
                ended_at=p.ended_at,
            )
        )
        return
    if row.match_id != p.match_id:
        raise SyncRejection(INVALID_STATE, "an innings cannot move to another match")
    if row.innings_number != p.innings_number:
        raise SyncRejection(INVALID_STATE, "innings_number cannot be changed")
    if (row.batting_team_id, row.bowling_team_id) != (p.batting_team_id, p.bowling_team_id):
        raise SyncRejection(INVALID_STATE, "batting and bowling teams cannot be changed")
    row.started_at = p.started_at
    row.ended_at = p.ended_at
