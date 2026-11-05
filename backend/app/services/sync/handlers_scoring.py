"""Sync handlers for deliveries, decisions and trajectories (API_CONTRACT §5.3, SCORING_RULES)."""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.delivery import Delivery
from app.models.delivery_decision import DeliveryDecision
from app.models.innings import Innings
from app.models.match_player import MatchPlayer
from app.models.trajectory_snapshot import TrajectorySnapshot
from app.models.wicket_detection import WicketDetection
from app.schemas.sync import (
    DeliveryDecisionPayload,
    DeliveryPayload,
    DeliveryVoidPayload,
    TrajectorySnapshotPayload,
)
from app.services import scoring
from app.services.scoring import DeliveryFacts, DeliveryScore
from app.services.sync.context import (
    SyncContext,
    require_owned_delivery,
    require_owned_innings,
)
from app.services.sync.errors import (
    ENTITY_NOT_FOUND,
    INNINGS_CLOSED,
    INVALID_DELIVERY,
    INVALID_REFERENCE,
    INVALID_STATE,
    NOT_LAST_DELIVERY,
    OVER_LIMIT_EXCEEDED,
    PARENT_NOT_FOUND,
    SyncRejection,
)


async def _load_scores(
    session: AsyncSession, innings_id: uuid.UUID
) -> tuple[list[DeliveryScore], int]:
    """All deliveries of an innings as score rows, plus the highest sequence ever used."""
    rows = await session.execute(
        select(
            Delivery.delivery_sequence,
            Delivery.runs_bat,
            Delivery.runs_extras,
            Delivery.is_wicket,
            Delivery.is_wide,
            Delivery.is_no_ball,
            Delivery.is_voided,
        ).where(Delivery.innings_id == innings_id)
    )
    scores: list[DeliveryScore] = []
    max_sequence = 0
    for sequence, runs_bat, runs_extras, is_wicket, is_wide, is_no_ball, is_voided in rows:
        max_sequence = max(max_sequence, sequence)
        scores.append(
            DeliveryScore(
                runs_bat=runs_bat,
                runs_extras=runs_extras,
                is_wicket=is_wicket,
                is_wide=is_wide,
                is_no_ball=is_no_ball,
                is_voided=is_voided,
            )
        )
    return scores, max_sequence


async def _refresh_innings_totals(session: AsyncSession, innings: Innings) -> None:
    await session.flush()
    scores, _ = await _load_scores(session, innings.id)
    totals = scoring.aggregate(scores)
    innings.total_runs = totals.total_runs
    innings.wickets = totals.wickets
    innings.legal_balls = totals.legal_balls


async def upsert_delivery(ctx: SyncContext, p: DeliveryPayload) -> None:
    session = ctx.session

    existing = await session.get(Delivery, p.id)
    if existing is not None:
        # Create-only: a repeat of an existing delivery is a no-op, but never for someone else's.
        await require_owned_delivery(ctx, p.id)
        return

    innings, match = await require_owned_innings(ctx, p.innings_id, lock=True)

    problem = scoring.validate_delivery(
        DeliveryFacts(
            runs_bat=p.runs_bat,
            runs_extras=p.runs_extras,
            is_wide=p.is_wide,
            is_no_ball=p.is_no_ball,
            is_bye=p.is_bye,
            is_leg_bye=p.is_leg_bye,
            is_wicket=p.is_wicket,
            dismissal_type=p.dismissal_type.value if p.dismissal_type else None,
            striker_id=p.striker_id,
            non_striker_id=p.non_striker_id,
            dismissed_player_id=p.dismissed_player_id,
        )
    )
    if problem is not None:
        raise SyncRejection(INVALID_DELIVERY, problem)

    wanted = {p.bowler_id, p.striker_id}
    for optional in (p.non_striker_id, p.dismissed_player_id):
        if optional is not None:
            wanted.add(optional)
    present = set(
        await session.scalars(
            select(MatchPlayer.player_id).where(
                MatchPlayer.match_id == match.id, MatchPlayer.player_id.in_(wanted)
            )
        )
    )
    if present != wanted:
        raise SyncRejection(
            INVALID_REFERENCE, "bowler, striker and non-striker must be players of this match"
        )

    if p.wicket_detection_id is not None:
        detection = await session.get(WicketDetection, p.wicket_detection_id)
        if detection is None:
            raise SyncRejection(PARENT_NOT_FOUND, "the wicket detection does not exist")
        if detection.match_id != match.id:
            raise SyncRejection(INVALID_REFERENCE, "the wicket detection belongs to another match")

    if innings.ended_at is not None:
        raise SyncRejection(INNINGS_CLOSED, "the innings has ended")

    scores, max_sequence = await _load_scores(session, innings.id)
    legal_before = scoring.aggregate(scores).legal_balls
    max_legal_balls = match.overs_per_innings * scoring.BALLS_PER_OVER
    if legal_before >= max_legal_balls:
        raise SyncRejection(
            OVER_LIMIT_EXCEEDED, f"the innings already has {max_legal_balls} legal balls"
        )

    legal = scoring.is_legal(is_wide=p.is_wide, is_no_ball=p.is_no_ball)
    position = scoring.derive_position(
        legal_balls_before=legal_before, max_sequence=max_sequence, legal=legal
    )
    session.add(
        Delivery(
            id=p.id,
            innings_id=innings.id,
            wicket_detection_id=p.wicket_detection_id,
            delivery_sequence=position.delivery_sequence,
            over_number=position.over_number,
            legal_ball_number=position.legal_ball_number,
            bowler_id=p.bowler_id,
            striker_id=p.striker_id,
            non_striker_id=p.non_striker_id,
            dismissed_player_id=p.dismissed_player_id,
            runs_bat=p.runs_bat,
            runs_extras=p.runs_extras,
            is_wide=p.is_wide,
            is_no_ball=p.is_no_ball,
            is_bye=p.is_bye,
            is_leg_bye=p.is_leg_bye,
            is_wicket=p.is_wicket,
            dismissal_type=p.dismissal_type.value if p.dismissal_type else None,
            speed_kmph=p.speed_kmph,
            speed_confidence=p.speed_confidence,
            ball_tracking_confidence=p.ball_tracking_confidence,
            pose_tracking_confidence=p.pose_tracking_confidence,
            wicket_tracking_confidence=p.wicket_tracking_confidence,
            is_voided=False,
            created_at=p.created_at or ctx.now,
        )
    )
    await _refresh_innings_totals(session, innings)


async def void_delivery(ctx: SyncContext, p: DeliveryVoidPayload) -> None:
    session = ctx.session
    row = await session.get(Delivery, p.id)
    if row is None:
        raise SyncRejection(ENTITY_NOT_FOUND, "the delivery does not exist")
    innings, _match = await require_owned_innings(ctx, row.innings_id, lock=True)
    await session.refresh(row)  # state may have changed while waiting for the innings lock
    if row.is_voided:
        return  # idempotent

    last_active = await session.scalar(
        select(Delivery.delivery_sequence)
        .where(Delivery.innings_id == innings.id, Delivery.is_voided.is_(False))
        .order_by(Delivery.delivery_sequence.desc())
        .limit(1)
    )
    if last_active != row.delivery_sequence:
        raise SyncRejection(
            NOT_LAST_DELIVERY, "only the last non-voided delivery of an innings can be voided"
        )
    row.is_voided = True
    row.voided_at = ctx.now
    row.void_reason = p.void_reason
    await _refresh_innings_totals(session, innings)


async def upsert_delivery_decision(ctx: SyncContext, p: DeliveryDecisionPayload) -> None:
    await require_owned_delivery(ctx, p.delivery_id)
    row = await ctx.session.get(DeliveryDecision, p.id)
    if row is not None and row.delivery_id != p.delivery_id:
        raise SyncRejection(INVALID_STATE, "a decision cannot move to another delivery")
    if row is None:
        row = DeliveryDecision(
            id=p.id, delivery_id=p.delivery_id, created_at=p.created_at or ctx.now
        )
        ctx.session.add(row)
    elif p.created_at is not None:
        row.created_at = p.created_at
    row.decision_type = p.decision_type.value
    row.automated_result = p.automated_result
    row.final_result = p.final_result
    row.confidence = p.confidence
    row.decision_status = p.decision_status.value
    row.decision_source = p.decision_source.value
    row.evidence = p.evidence
    row.updated_at = ctx.now


async def upsert_trajectory_snapshot(ctx: SyncContext, p: TrajectorySnapshotPayload) -> None:
    await require_owned_delivery(ctx, p.delivery_id)
    row = await ctx.session.get(TrajectorySnapshot, p.id)
    if row is not None and row.delivery_id != p.delivery_id:
        raise SyncRejection(INVALID_STATE, "a trajectory cannot move to another delivery")
    if row is None:
        row = TrajectorySnapshot(
            id=p.id, delivery_id=p.delivery_id, created_at=p.created_at or ctx.now
        )
        ctx.session.add(row)
    elif p.created_at is not None:
        row.created_at = p.created_at
    row.sampling_fps = p.sampling_fps
    row.points_compressed = p.points_compressed
    row.model_version = p.model_version
