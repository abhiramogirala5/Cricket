"""Importing this package registers every table on ``Base.metadata``."""

from app.models.delivery import Delivery
from app.models.delivery_decision import DeliveryDecision
from app.models.innings import Innings
from app.models.match import Match
from app.models.match_player import MatchPlayer
from app.models.match_rules import MatchRules
from app.models.player import Player
from app.models.refresh_token import RefreshToken
from app.models.replay_clip import ReplayClip
from app.models.scene_scan import SceneScan
from app.models.sync_event import SyncEvent
from app.models.team import Team
from app.models.toss import Toss
from app.models.trajectory_snapshot import TrajectorySnapshot
from app.models.user import User
from app.models.wicket_detection import WicketDetection

__all__ = [
    "Delivery",
    "DeliveryDecision",
    "Innings",
    "Match",
    "MatchPlayer",
    "MatchRules",
    "Player",
    "RefreshToken",
    "ReplayClip",
    "SceneScan",
    "SyncEvent",
    "Team",
    "Toss",
    "TrajectorySnapshot",
    "User",
    "WicketDetection",
]
