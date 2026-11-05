"""Read models returned by the GET endpoints (API_CONTRACT §4 and §5.3 "Read" shapes)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from app.models.enums import (
    BattingHand,
    DecisionSource,
    DecisionStatus,
    DecisionType,
    DismissalType,
    MatchStatus,
    TossDecision,
    TossSide,
    WicketFamily,
)
from app.schemas.common import ApiModel


class PlayerRead(ApiModel):
    id: uuid.UUID
    display_name: str
    batting_hand: BattingHand
    declared_height_cm: int | None
    created_at: datetime
    updated_at: datetime


class TeamRead(ApiModel):
    id: uuid.UUID
    name: str
    created_at: datetime
    updated_at: datetime


class MatchRead(ApiModel):
    id: uuid.UUID
    owner_id: uuid.UUID
    team_a_id: uuid.UUID
    team_b_id: uuid.UUID
    match_name: str | None
    location_name: str | None
    scheduled_at: datetime | None
    started_at: datetime | None
    completed_at: datetime | None
    status: MatchStatus
    overs_per_innings: int
    local_rules_profile: str
    winner_team_id: uuid.UUID | None
    result_summary: str | None
    created_at: datetime
    updated_at: datetime


class MatchPlayerRead(ApiModel):
    match_id: uuid.UUID
    player_id: uuid.UUID
    team_id: uuid.UUID
    batting_hand: BattingHand
    declared_height_cm: int | None
    batting_order: int | None
    is_captain: bool
    is_wicketkeeper: bool


class MatchRulesRead(ApiModel):
    match_id: uuid.UUID
    wide_enabled: bool
    no_ball_enabled: bool
    front_foot_no_ball_enabled: bool
    edge_review_enabled: bool
    lbw_review_enabled: bool
    full_toss_above_waist_is_no_ball: bool
    bounced_above_shoulder_is_no_ball: bool
    max_bouncers_per_over: int | None
    lateral_reach_multiplier: float


class SceneScanRead(ApiModel):
    id: uuid.UUID
    match_id: uuid.UUID
    camera_device_model: str | None
    capture_fps: int | None
    scan_duration_ms: int
    ground_plane: dict[str, Any] | None
    pitch_direction: dict[str, Any] | None
    batsman_plane: dict[str, Any] | None
    overall_confidence: float
    model_version: str
    created_at: datetime


class WicketDetectionRead(ApiModel):
    id: uuid.UUID
    match_id: uuid.UUID
    scene_scan_id: uuid.UUID | None
    wicket_family: WicketFamily
    bounding_box: dict[str, Any]
    target_polygon: list[Any]
    target_plane: dict[str, Any] | None
    ground_contact_line: dict[str, Any] | None
    object_confidence: float
    temporal_stability: float
    context_confidence: float
    final_confidence: float
    is_active: bool
    model_version: str
    detected_at: datetime


class TossRead(ApiModel):
    id: uuid.UUID
    match_id: uuid.UUID
    called_by_player_id: uuid.UUID | None
    call_choice: TossSide
    result: TossSide
    winner_team_id: uuid.UUID | None
    winner_decision: TossDecision | None
    created_at: datetime


class InningsRead(ApiModel):
    id: uuid.UUID
    match_id: uuid.UUID
    innings_number: int
    batting_team_id: uuid.UUID
    bowling_team_id: uuid.UUID
    total_runs: int
    wickets: int
    legal_balls: int
    started_at: datetime
    ended_at: datetime | None


class DeliveryRead(ApiModel):
    id: uuid.UUID
    innings_id: uuid.UUID
    wicket_detection_id: uuid.UUID | None
    delivery_sequence: int
    over_number: int
    legal_ball_number: int | None
    bowler_id: uuid.UUID
    striker_id: uuid.UUID
    non_striker_id: uuid.UUID | None
    dismissed_player_id: uuid.UUID | None
    runs_bat: int
    runs_extras: int
    is_wide: bool
    is_no_ball: bool
    is_bye: bool
    is_leg_bye: bool
    is_wicket: bool
    dismissal_type: DismissalType | None
    speed_kmph: float | None
    speed_confidence: float | None
    ball_tracking_confidence: float | None
    pose_tracking_confidence: float | None
    wicket_tracking_confidence: float | None
    is_voided: bool
    voided_at: datetime | None
    void_reason: str | None
    created_at: datetime


class DeliveryDecisionRead(ApiModel):
    id: uuid.UUID
    delivery_id: uuid.UUID
    decision_type: DecisionType
    automated_result: str | None
    final_result: str | None
    confidence: float | None
    decision_status: DecisionStatus
    decision_source: DecisionSource
    evidence: dict[str, Any] | None
    created_at: datetime
    updated_at: datetime


class TrajectorySnapshotRead(ApiModel):
    id: uuid.UUID
    delivery_id: uuid.UUID
    sampling_fps: int
    points_compressed: list[Any]
    model_version: str
    created_at: datetime


class TeamBrief(ApiModel):
    id: uuid.UUID
    name: str


class InningsBrief(ApiModel):
    id: uuid.UUID
    innings_number: int
    batting_team_id: uuid.UUID
    bowling_team_id: uuid.UUID
    total_runs: int
    wickets: int
    legal_balls: int
    ended_at: datetime | None


class MatchSummary(ApiModel):
    id: uuid.UUID
    match_name: str | None
    location_name: str | None
    status: MatchStatus
    overs_per_innings: int
    team_a: TeamBrief
    team_b: TeamBrief
    started_at: datetime | None
    completed_at: datetime | None
    winner_team_id: uuid.UUID | None
    result_summary: str | None
    innings: list[InningsBrief]
    created_at: datetime
    updated_at: datetime


class MatchSnapshot(ApiModel):
    match: MatchRead
    rules: MatchRulesRead | None
    teams: list[TeamRead]
    players: list[PlayerRead]
    match_players: list[MatchPlayerRead]
    toss: TossRead | None
    innings: list[InningsRead]
    deliveries: list[DeliveryRead]
    delivery_decisions: list[DeliveryDecisionRead]
    scene_scans: list[SceneScanRead]
    wicket_detections: list[WicketDetectionRead]
    trajectory_snapshots: list[TrajectorySnapshotRead]
