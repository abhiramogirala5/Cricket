"""Maps ``(entity_type, action)`` to its payload schema and handler."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any

from app.models.enums import EntityType, SyncAction
from app.schemas import sync as schemas
from app.schemas.sync import PayloadModel
from app.services.sync import handlers_roster as roster
from app.services.sync import handlers_scoring as scoring
from app.services.sync.context import SyncContext

Handler = Callable[[SyncContext, Any], Awaitable[None]]


@dataclass(frozen=True, slots=True)
class Route:
    schema: type[PayloadModel]
    handler: Handler


ROUTES: dict[tuple[EntityType, SyncAction], Route] = {
    (EntityType.PLAYER, SyncAction.UPSERT): Route(schemas.PlayerPayload, roster.upsert_player),
    (EntityType.TEAM, SyncAction.UPSERT): Route(schemas.TeamPayload, roster.upsert_team),
    (EntityType.MATCH, SyncAction.UPSERT): Route(schemas.MatchPayload, roster.upsert_match),
    (EntityType.MATCH, SyncAction.DELETE): Route(schemas.MatchDeletePayload, roster.delete_match),
    (EntityType.MATCH_PLAYER, SyncAction.UPSERT): Route(
        schemas.MatchPlayerPayload, roster.upsert_match_player
    ),
    (EntityType.MATCH_RULES, SyncAction.UPSERT): Route(
        schemas.MatchRulesPayload, roster.upsert_match_rules
    ),
    (EntityType.SCENE_SCAN, SyncAction.UPSERT): Route(
        schemas.SceneScanPayload, roster.upsert_scene_scan
    ),
    (EntityType.WICKET_DETECTION, SyncAction.UPSERT): Route(
        schemas.WicketDetectionPayload, roster.upsert_wicket_detection
    ),
    (EntityType.TOSS, SyncAction.UPSERT): Route(schemas.TossPayload, roster.upsert_toss),
    (EntityType.INNINGS, SyncAction.UPSERT): Route(schemas.InningsPayload, roster.upsert_innings),
    (EntityType.DELIVERY, SyncAction.UPSERT): Route(
        schemas.DeliveryPayload, scoring.upsert_delivery
    ),
    (EntityType.DELIVERY, SyncAction.VOID): Route(
        schemas.DeliveryVoidPayload, scoring.void_delivery
    ),
    (EntityType.DELIVERY_DECISION, SyncAction.UPSERT): Route(
        schemas.DeliveryDecisionPayload, scoring.upsert_delivery_decision
    ),
    (EntityType.TRAJECTORY_SNAPSHOT, SyncAction.UPSERT): Route(
        schemas.TrajectorySnapshotPayload, scoring.upsert_trajectory_snapshot
    ),
}
