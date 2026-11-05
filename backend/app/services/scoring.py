"""Pure delivery rules and aggregates. No I/O, no SQLAlchemy.

Implements docs/SCORING_RULES.md §2 (validation rules 1-13), §3 (derived fields) and §5
(aggregates). The Flutter app implements the same rules; both are tested against
docs/scoring_test_vectors.json.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from app.models.enums import DismissalType

BAT_RUNS_MAX = 7
EXTRAS_MAX = 10
BALLS_PER_OVER = 6

_ALLOWED_ON_NO_BALL = frozenset({DismissalType.RUN_OUT})
_ALLOWED_ON_WIDE = frozenset(
    {DismissalType.RUN_OUT, DismissalType.STUMPED, DismissalType.HIT_WICKET}
)


@dataclass(frozen=True, slots=True)
class DeliveryFacts:
    """Everything rules 1-13 need. Player ids are opaque values (compared with ``==``)."""

    runs_bat: int
    runs_extras: int
    is_wide: bool
    is_no_ball: bool
    is_bye: bool
    is_leg_bye: bool
    is_wicket: bool
    dismissal_type: str | None
    striker_id: object
    non_striker_id: object | None
    dismissed_player_id: object | None


def is_legal(*, is_wide: bool, is_no_ball: bool) -> bool:
    """A legal ball counts towards the over; wides and no-balls do not."""
    return not is_wide and not is_no_ball


def validate_delivery(d: DeliveryFacts) -> str | None:
    """Return the message of the first violated rule, or ``None`` if the delivery is valid."""
    penalty = 1 if (d.is_wide or d.is_no_ball) else 0
    byes = d.is_bye or d.is_leg_bye

    # 1
    if not 0 <= d.runs_bat <= BAT_RUNS_MAX:
        return f"runs_bat must be between 0 and {BAT_RUNS_MAX}"
    if not 0 <= d.runs_extras <= EXTRAS_MAX:
        return f"runs_extras must be between 0 and {EXTRAS_MAX}"
    # 2-4
    if d.is_wide and d.is_no_ball:
        return "a delivery cannot be both a wide and a no-ball"
    if d.is_bye and d.is_leg_bye:
        return "a delivery cannot be both a bye and a leg-bye"
    if d.is_wide and byes:
        return "all runs off a wide are wides: byes and leg-byes are not allowed"
    # 5-6
    if d.is_wide and d.runs_bat > 0:
        return "wide deliveries cannot have bat runs"
    if byes and d.runs_bat > 0:
        return "byes and leg-byes cannot have bat runs"
    # 7-9
    if d.runs_extras < penalty:
        return "wides and no-balls carry at least 1 extra run"
    if byes and d.runs_extras < penalty + 1:
        return "a bye or leg-bye means at least one bye run was taken"
    if not (d.is_wide or d.is_no_ball or byes) and d.runs_extras != 0:
        return "extras require a wide, no-ball, bye or leg-bye flag"
    # 10
    if d.is_wicket and d.dismissal_type is None:
        return "a wicket needs a dismissal_type"
    if not d.is_wicket and d.dismissal_type is not None:
        return "dismissal_type is only allowed on a wicket"
    # 11
    if d.is_wicket and d.dismissal_type is not None:
        try:
            dismissal = DismissalType(d.dismissal_type)
        except ValueError:
            return f"unknown dismissal_type {d.dismissal_type!r}"
        if d.is_no_ball and dismissal not in _ALLOWED_ON_NO_BALL:
            return f"{dismissal.value} is not allowed on a no-ball"
        if d.is_wide and dismissal not in _ALLOWED_ON_WIDE:
            return f"{dismissal.value} is not allowed on a wide"
        # 12
        if d.dismissed_player_id is None:
            return "a wicket needs dismissed_player_id"
        is_striker = d.dismissed_player_id == d.striker_id
        is_non_striker = d.non_striker_id is not None and d.dismissed_player_id == d.non_striker_id
        if not (is_striker or is_non_striker):
            return "dismissed_player_id must be the striker or the non-striker"
        if is_non_striker and not is_striker and dismissal is not DismissalType.RUN_OUT:
            return "only a run-out can dismiss the non-striker"
    # 13
    if d.non_striker_id is not None and d.striker_id == d.non_striker_id:
        return "striker and non-striker must be different players"
    return None


@dataclass(frozen=True, slots=True)
class Position:
    delivery_sequence: int
    over_number: int
    legal_ball_number: int | None


def derive_position(*, legal_balls_before: int, max_sequence: int, legal: bool) -> Position:
    """Derived fields of a new delivery (SCORING_RULES §3).

    ``max_sequence`` is the highest ``delivery_sequence`` ever recorded in the innings, voided
    deliveries included (0 when there is none): sequences are never reused.
    """
    return Position(
        delivery_sequence=max_sequence + 1,
        over_number=legal_balls_before // BALLS_PER_OVER,
        legal_ball_number=(legal_balls_before % BALLS_PER_OVER) + 1 if legal else None,
    )


@dataclass(frozen=True, slots=True)
class DeliveryScore:
    """The columns an innings aggregate needs."""

    runs_bat: int
    runs_extras: int
    is_wicket: bool
    is_wide: bool
    is_no_ball: bool
    is_voided: bool = False


@dataclass(frozen=True, slots=True)
class Aggregate:
    total_runs: int
    wickets: int
    legal_balls: int


def aggregate(deliveries: Iterable[DeliveryScore]) -> Aggregate:
    """Innings totals over the non-voided deliveries (SCORING_RULES §5)."""
    total_runs = wickets = legal_balls = 0
    for delivery in deliveries:
        if delivery.is_voided:
            continue
        total_runs += delivery.runs_bat + delivery.runs_extras
        if delivery.is_wicket:
            wickets += 1
        if is_legal(is_wide=delivery.is_wide, is_no_ball=delivery.is_no_ball):
            legal_balls += 1
    return Aggregate(total_runs=total_runs, wickets=wickets, legal_balls=legal_balls)
