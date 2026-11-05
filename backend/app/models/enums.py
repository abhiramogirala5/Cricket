"""String enums shared by models, schemas and services (wire values are UPPER_SNAKE_CASE)."""

from __future__ import annotations

from enum import StrEnum


class BattingHand(StrEnum):
    LEFT = "LEFT"
    RIGHT = "RIGHT"
    UNKNOWN = "UNKNOWN"


class MatchStatus(StrEnum):
    DRAFT = "DRAFT"
    SCANNING = "SCANNING"
    READY = "READY"
    LIVE = "LIVE"
    COMPLETED = "COMPLETED"
    ABANDONED = "ABANDONED"

    @property
    def is_terminal(self) -> bool:
        return self in (MatchStatus.COMPLETED, MatchStatus.ABANDONED)


class DismissalType(StrEnum):
    BOWLED = "BOWLED"
    CAUGHT = "CAUGHT"
    LBW = "LBW"
    RUN_OUT = "RUN_OUT"
    STUMPED = "STUMPED"
    HIT_WICKET = "HIT_WICKET"


class TossSide(StrEnum):
    HEADS = "HEADS"
    TAILS = "TAILS"


class TossDecision(StrEnum):
    BAT = "BAT"
    BOWL = "BOWL"


class WicketFamily(StrEnum):
    TRADITIONAL_STUMPS = "TRADITIONAL_STUMPS"
    CHAIR = "CHAIR"
    BRICK_STACK = "BRICK_STACK"
    BOTTLE_STACK = "BOTTLE_STACK"
    CONE_STACK = "CONE_STACK"
    BUCKET = "BUCKET"
    BAG_OR_OBJECT = "BAG_OR_OBJECT"
    WALL_TARGET = "WALL_TARGET"
    UNKNOWN_PHYSICAL_OBJECT = "UNKNOWN_PHYSICAL_OBJECT"


class DecisionType(StrEnum):
    WIDE = "WIDE"
    NO_BALL_HEIGHT = "NO_BALL_HEIGHT"
    NO_BALL_FRONT_FOOT = "NO_BALL_FRONT_FOOT"
    EDGE = "EDGE"
    LBW = "LBW"
    WICKET_HIT = "WICKET_HIT"


class DecisionStatus(StrEnum):
    AUTO_CALL = "AUTO_CALL"
    REVIEW_RECOMMENDED = "REVIEW_RECOMMENDED"
    INCONCLUSIVE = "INCONCLUSIVE"
    MANUAL_OVERRIDE = "MANUAL_OVERRIDE"


class DecisionSource(StrEnum):
    AI_ASSIST = "AI_ASSIST"
    MANUAL = "MANUAL"


class EntityType(StrEnum):
    PLAYER = "PLAYER"
    TEAM = "TEAM"
    MATCH = "MATCH"
    MATCH_PLAYER = "MATCH_PLAYER"
    MATCH_RULES = "MATCH_RULES"
    SCENE_SCAN = "SCENE_SCAN"
    WICKET_DETECTION = "WICKET_DETECTION"
    TOSS = "TOSS"
    INNINGS = "INNINGS"
    DELIVERY = "DELIVERY"
    DELIVERY_DECISION = "DELIVERY_DECISION"
    TRAJECTORY_SNAPSHOT = "TRAJECTORY_SNAPSHOT"


class SyncAction(StrEnum):
    UPSERT = "UPSERT"
    VOID = "VOID"
    DELETE = "DELETE"


class SyncStatus(StrEnum):
    APPLIED = "APPLIED"
    DUPLICATE = "DUPLICATE"
    REJECTED = "REJECTED"


class ReplayStatus(StrEnum):
    """Where the replay file of a delivery is: announced but not uploaded, or stored."""

    PENDING = "PENDING"
    READY = "READY"
