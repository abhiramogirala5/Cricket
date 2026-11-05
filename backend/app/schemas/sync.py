"""Sync request/response envelopes and the strict per-entity payload schemas (API_CONTRACT §5)."""

from __future__ import annotations

import json
import uuid
from datetime import UTC, datetime
from typing import Annotated, Any, Self

from pydantic import (
    AfterValidator,
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    model_validator,
)

from app.models.enums import (
    BattingHand,
    DecisionSource,
    DecisionStatus,
    DecisionType,
    DismissalType,
    EntityType,
    MatchStatus,
    SyncAction,
    SyncStatus,
    TossDecision,
    TossSide,
    WicketFamily,
)
from app.schemas.common import ApiModel, RequestModel

MAX_EVENTS_PER_BATCH = 100
MAX_JSON_BYTES = 64 * 1024
MAX_TRAJECTORY_POINTS = 600


# --------------------------------------------------------------------------- envelope


class SyncEventIn(RequestModel):
    event_id: uuid.UUID
    entity_type: Annotated[str, Field(min_length=1, max_length=40)]
    action: Annotated[str, Field(min_length=1, max_length=20)]
    payload: dict[str, Any]
    client_created_at: AwareDatetime


class SyncPushRequest(RequestModel):
    events: Annotated[list[SyncEventIn], Field(min_length=1, max_length=MAX_EVENTS_PER_BATCH)]


class SyncEventError(ApiModel):
    code: str
    message: str


class SyncEventResult(ApiModel):
    event_id: uuid.UUID
    status: SyncStatus
    error: SyncEventError | None = None


class SyncPushResponse(ApiModel):
    results: list[SyncEventResult]
    server_time: datetime


# --------------------------------------------------------------------------- shared types


def _to_utc(value: datetime) -> datetime:
    return value.astimezone(UTC)


def _limit_json_size(value: dict[str, Any]) -> dict[str, Any]:
    if len(json.dumps(value, separators=(",", ":"))) > MAX_JSON_BYTES:
        raise ValueError(f"JSON object is larger than {MAX_JSON_BYTES} bytes")
    return value


Timestamp = Annotated[AwareDatetime, AfterValidator(_to_utc)]
JsonObject = Annotated[dict[str, Any], AfterValidator(_limit_json_size)]
Unit = Annotated[float, Field(ge=0, le=1)]
Height = Annotated[int, Field(ge=100, le=230)]
ModelVersion = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)
]


class PayloadModel(BaseModel):
    """Base of all sync payloads: strict types, unknown fields rejected.

    Validate with ``Model.model_validate_json(json.dumps(payload))`` so JSON-mode strictness
    applies (``"3"`` is not an int, ``1`` is not a bool, but ``"…"`` is still a valid
    UUID/timestamp/enum).
    """

    model_config = ConfigDict(extra="forbid", strict=True)


class BoundingBoxPayload(PayloadModel):
    x: Unit
    y: Unit
    width: Unit
    height: Unit


class PointPayload(PayloadModel):
    x: Unit
    y: Unit


# --------------------------------------------------------------------------- entities


class PlayerPayload(PayloadModel):
    id: uuid.UUID
    display_name: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)
    ]
    batting_hand: BattingHand = BattingHand.UNKNOWN
    declared_height_cm: Height | None = None


class TeamPayload(PayloadModel):
    id: uuid.UUID
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


class MatchPayload(PayloadModel):
    id: uuid.UUID
    team_a_id: uuid.UUID
    team_b_id: uuid.UUID
    match_name: Annotated[str, Field(max_length=150)] | None = None
    location_name: Annotated[str, Field(max_length=255)] | None = None
    scheduled_at: Timestamp | None = None
    started_at: Timestamp | None = None
    completed_at: Timestamp | None = None
    status: MatchStatus = MatchStatus.DRAFT
    overs_per_innings: Annotated[int, Field(ge=1, le=50)] = 6
    local_rules_profile: Annotated[str, Field(min_length=1, max_length=40)] = "CASUAL_GULLY"
    winner_team_id: uuid.UUID | None = None
    result_summary: Annotated[str, Field(max_length=255)] | None = None

    @model_validator(mode="after")
    def _teams_differ(self) -> Self:
        if self.team_a_id == self.team_b_id:
            raise ValueError("team_a_id and team_b_id must differ")
        return self


class MatchDeletePayload(PayloadModel):
    id: uuid.UUID


class MatchPlayerPayload(PayloadModel):
    match_id: uuid.UUID
    player_id: uuid.UUID
    team_id: uuid.UUID
    batting_hand: BattingHand = BattingHand.UNKNOWN
    declared_height_cm: Height | None = None
    batting_order: Annotated[int, Field(ge=1, le=30)] | None = None
    is_captain: bool = False
    is_wicketkeeper: bool = False


class MatchRulesPayload(PayloadModel):
    match_id: uuid.UUID
    wide_enabled: bool = True
    no_ball_enabled: bool = True
    front_foot_no_ball_enabled: bool = False
    edge_review_enabled: bool = True
    lbw_review_enabled: bool = True
    full_toss_above_waist_is_no_ball: bool = True
    bounced_above_shoulder_is_no_ball: bool = False
    max_bouncers_per_over: Annotated[int, Field(ge=0, le=6)] | None = None
    lateral_reach_multiplier: Annotated[float, Field(ge=0.20, le=1.50)] = 0.60


class SceneScanPayload(PayloadModel):
    id: uuid.UUID
    match_id: uuid.UUID
    camera_device_model: Annotated[str, Field(max_length=150)] | None = None
    capture_fps: Annotated[int, Field(ge=1, le=240)] | None = None
    scan_duration_ms: Annotated[int, Field(ge=0, le=120_000)]
    ground_plane: JsonObject | None = None
    pitch_direction: JsonObject | None = None
    batsman_plane: JsonObject | None = None
    overall_confidence: Unit
    model_version: ModelVersion
    created_at: Timestamp | None = None


class WicketDetectionPayload(PayloadModel):
    id: uuid.UUID
    match_id: uuid.UUID
    scene_scan_id: uuid.UUID | None = None
    wicket_family: WicketFamily
    bounding_box: BoundingBoxPayload
    target_polygon: Annotated[list[PointPayload], Field(min_length=3, max_length=32)]
    target_plane: JsonObject | None = None
    ground_contact_line: JsonObject | None = None
    object_confidence: Unit
    temporal_stability: Unit
    context_confidence: Unit
    final_confidence: Unit
    is_active: bool = True
    model_version: ModelVersion
    detected_at: Timestamp | None = None


class TossPayload(PayloadModel):
    id: uuid.UUID
    match_id: uuid.UUID
    called_by_player_id: uuid.UUID | None = None
    call_choice: TossSide
    result: TossSide
    winner_team_id: uuid.UUID | None = None
    winner_decision: TossDecision | None = None


class InningsPayload(PayloadModel):
    id: uuid.UUID
    match_id: uuid.UUID
    innings_number: Annotated[int, Field(ge=1, le=4)]
    batting_team_id: uuid.UUID
    bowling_team_id: uuid.UUID
    started_at: Timestamp
    ended_at: Timestamp | None = None

    @model_validator(mode="after")
    def _consistent(self) -> Self:
        if self.batting_team_id == self.bowling_team_id:
            raise ValueError("batting_team_id and bowling_team_id must differ")
        if self.ended_at is not None and self.ended_at < self.started_at:
            raise ValueError("ended_at cannot be before started_at")
        return self


class DeliveryPayload(PayloadModel):
    id: uuid.UUID
    innings_id: uuid.UUID
    bowler_id: uuid.UUID
    striker_id: uuid.UUID
    non_striker_id: uuid.UUID | None = None
    runs_bat: int
    runs_extras: int
    is_wide: bool = False
    is_no_ball: bool = False
    is_bye: bool = False
    is_leg_bye: bool = False
    is_wicket: bool = False
    dismissal_type: DismissalType | None = None
    dismissed_player_id: uuid.UUID | None = None
    wicket_detection_id: uuid.UUID | None = None
    speed_kmph: Annotated[float, Field(ge=0, le=250)] | None = None
    speed_confidence: Unit | None = None
    ball_tracking_confidence: Unit | None = None
    pose_tracking_confidence: Unit | None = None
    wicket_tracking_confidence: Unit | None = None
    created_at: Timestamp | None = None

    # runs_bat / runs_extras ranges are rule 1 of SCORING_RULES.md and are reported as
    # INVALID_DELIVERY by the rules engine, not as INVALID_PAYLOAD.

    @model_validator(mode="after")
    def _dismissed_player_needs_wicket(self) -> Self:
        # API_CONTRACT §5.3: dismissed_player_id is "required iff is_wicket".
        if not self.is_wicket and self.dismissed_player_id is not None:
            raise ValueError("dismissed_player_id is only allowed when is_wicket is true")
        return self


class DeliveryVoidPayload(PayloadModel):
    id: uuid.UUID
    void_reason: Annotated[str, Field(max_length=100)] | None = None


class DeliveryDecisionPayload(PayloadModel):
    id: uuid.UUID
    delivery_id: uuid.UUID
    decision_type: DecisionType
    automated_result: Annotated[str, Field(max_length=40)] | None = None
    final_result: Annotated[str, Field(max_length=40)] | None = None
    confidence: Unit | None = None
    decision_status: DecisionStatus
    decision_source: DecisionSource
    evidence: JsonObject | None = None
    created_at: Timestamp | None = None


def _check_points(points: list[list[float]]) -> list[list[float]]:
    for point in points:
        if point[0] < 0:
            raise ValueError("timestamp_ms must be >= 0")
        if not 0 <= point[3] <= 1:
            raise ValueError("confidence must be between 0 and 1")
    return points


class TrajectorySnapshotPayload(PayloadModel):
    id: uuid.UUID
    delivery_id: uuid.UUID
    sampling_fps: Annotated[int, Field(ge=1, le=240)]
    points_compressed: Annotated[
        list[Annotated[list[float], Field(min_length=4, max_length=4)]],
        Field(max_length=MAX_TRAJECTORY_POINTS),
        AfterValidator(_check_points),
    ]
    model_version: ModelVersion
    created_at: Timestamp | None = None


# --------------------------------------------------------------------------- registry

PAYLOAD_SCHEMAS: dict[tuple[EntityType, SyncAction], type[PayloadModel]] = {
    (EntityType.PLAYER, SyncAction.UPSERT): PlayerPayload,
    (EntityType.TEAM, SyncAction.UPSERT): TeamPayload,
    (EntityType.MATCH, SyncAction.UPSERT): MatchPayload,
    (EntityType.MATCH, SyncAction.DELETE): MatchDeletePayload,
    (EntityType.MATCH_PLAYER, SyncAction.UPSERT): MatchPlayerPayload,
    (EntityType.MATCH_RULES, SyncAction.UPSERT): MatchRulesPayload,
    (EntityType.SCENE_SCAN, SyncAction.UPSERT): SceneScanPayload,
    (EntityType.WICKET_DETECTION, SyncAction.UPSERT): WicketDetectionPayload,
    (EntityType.TOSS, SyncAction.UPSERT): TossPayload,
    (EntityType.INNINGS, SyncAction.UPSERT): InningsPayload,
    (EntityType.DELIVERY, SyncAction.UPSERT): DeliveryPayload,
    (EntityType.DELIVERY, SyncAction.VOID): DeliveryVoidPayload,
    (EntityType.DELIVERY_DECISION, SyncAction.UPSERT): DeliveryDecisionPayload,
    (EntityType.TRAJECTORY_SNAPSHOT, SyncAction.UPSERT): TrajectorySnapshotPayload,
}
