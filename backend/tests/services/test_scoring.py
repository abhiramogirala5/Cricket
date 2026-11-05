"""Pure scoring rules, driven by docs/scoring_test_vectors.json."""

from __future__ import annotations

from typing import Any

import pytest

from app.services.scoring import (
    Aggregate,
    DeliveryFacts,
    DeliveryScore,
    aggregate,
    derive_position,
    is_legal,
    validate_delivery,
)
from tests.vectors import VECTORS, full_delivery

STRIKER = "striker"
NON_STRIKER = "non-striker"


def facts_from(partial: dict[str, Any]) -> DeliveryFacts:
    d = full_delivery(partial)
    dismissed = None
    if d["is_wicket"]:
        dismissed = STRIKER if d["dismissed"] == "STRIKER" else NON_STRIKER
    return DeliveryFacts(
        runs_bat=d["runs_bat"],
        runs_extras=d["runs_extras"],
        is_wide=d["is_wide"],
        is_no_ball=d["is_no_ball"],
        is_bye=d["is_bye"],
        is_leg_bye=d["is_leg_bye"],
        is_wicket=d["is_wicket"],
        dismissal_type=d["dismissal_type"],
        striker_id=STRIKER,
        non_striker_id=NON_STRIKER,
        dismissed_player_id=dismissed,
    )


@pytest.mark.parametrize("case", VECTORS["valid_deliveries"], ids=lambda c: c["name"])
def test_valid_deliveries(case: dict[str, Any]) -> None:
    assert validate_delivery(facts_from(case["delivery"])) is None


@pytest.mark.parametrize("case", VECTORS["invalid_deliveries"], ids=lambda c: c["name"])
def test_invalid_deliveries(case: dict[str, Any]) -> None:
    assert case["expect_error"] == "INVALID_DELIVERY"
    message = validate_delivery(facts_from(case["delivery"]))
    assert message, f"{case['name']} should be rejected"


def test_striker_equal_to_non_striker_is_invalid() -> None:
    same = DeliveryFacts(**{**_as_dict(facts_from({})), "non_striker_id": STRIKER})
    assert validate_delivery(same) == "striker and non-striker must be different players"


def test_non_striker_may_be_absent() -> None:
    d = _as_dict(facts_from({}))
    assert validate_delivery(DeliveryFacts(**{**d, "non_striker_id": None})) is None


def test_wicket_without_dismissed_player_is_invalid() -> None:
    d = _as_dict(facts_from({"is_wicket": True, "dismissal_type": "BOWLED"}))
    assert validate_delivery(DeliveryFacts(**{**d, "dismissed_player_id": None}))
    assert validate_delivery(DeliveryFacts(**{**d, "dismissed_player_id": "somebody else"}))


def test_run_out_may_dismiss_the_non_striker_but_nothing_else_may() -> None:
    run_out = _as_dict(
        facts_from({"is_wicket": True, "dismissal_type": "RUN_OUT", "dismissed": "NON_STRIKER"})
    )
    assert validate_delivery(DeliveryFacts(**run_out)) is None
    caught = {**run_out, "dismissal_type": "CAUGHT"}
    assert (
        validate_delivery(DeliveryFacts(**caught)) == "only a run-out can dismiss the non-striker"
    )


def test_unknown_dismissal_type_is_invalid() -> None:
    d = _as_dict(facts_from({"is_wicket": True, "dismissal_type": "BOWLED"}))
    assert validate_delivery(DeliveryFacts(**{**d, "dismissal_type": "OBSTRUCTING"}))


def test_derive_position_reuses_balls_but_not_sequences() -> None:
    assert derive_position(legal_balls_before=0, max_sequence=0, legal=True).legal_ball_number == 1
    p = derive_position(legal_balls_before=6, max_sequence=9, legal=True)
    assert (p.delivery_sequence, p.over_number, p.legal_ball_number) == (10, 1, 1)
    wide = derive_position(legal_balls_before=5, max_sequence=3, legal=False)
    assert (wide.delivery_sequence, wide.over_number, wide.legal_ball_number) == (4, 0, None)


def test_is_legal() -> None:
    assert is_legal(is_wide=False, is_no_ball=False)
    assert not is_legal(is_wide=True, is_no_ball=False)
    assert not is_legal(is_wide=False, is_no_ball=True)


def test_aggregate_ignores_voided_deliveries() -> None:
    rows = [
        DeliveryScore(runs_bat=4, runs_extras=0, is_wicket=False, is_wide=False, is_no_ball=False),
        DeliveryScore(runs_bat=0, runs_extras=1, is_wicket=False, is_wide=True, is_no_ball=False),
        DeliveryScore(runs_bat=0, runs_extras=0, is_wicket=True, is_wide=False, is_no_ball=False),
        DeliveryScore(
            runs_bat=6,
            runs_extras=0,
            is_wicket=True,
            is_wide=False,
            is_no_ball=False,
            is_voided=True,
        ),
    ]
    assert aggregate(rows) == Aggregate(total_runs=5, wickets=1, legal_balls=2)
    assert aggregate([]) == Aggregate(0, 0, 0)


def _as_dict(facts: DeliveryFacts) -> dict[str, Any]:
    return {name: getattr(facts, name) for name in DeliveryFacts.__slots__}


# ------------------------------------------------------------------ sequences (engine level)


def run_sequence(seq: dict[str, Any]) -> tuple[list[dict[str, Any]], list[str | None]]:
    """Replay a vector sequence with the pure functions. Returns (deliveries, step errors)."""
    max_balls = seq["overs_per_innings"] * 6
    deliveries: list[dict[str, Any]] = []  # every delivery incl. voided, in add order
    errors: list[str | None] = []

    def scores() -> list[DeliveryScore]:
        return [
            DeliveryScore(
                runs_bat=d["runs_bat"],
                runs_extras=d["runs_extras"],
                is_wicket=d["is_wicket"],
                is_wide=d["is_wide"],
                is_no_ball=d["is_no_ball"],
                is_voided=d["voided"],
            )
            for d in deliveries
        ]

    def last_active() -> dict[str, Any] | None:
        active = [d for d in deliveries if not d["voided"]]
        return max(active, key=lambda d: d["delivery_sequence"]) if active else None

    for step in seq["steps"]:
        error: str | None = None
        if step["op"] == "add":
            partial = step["delivery"]
            d = full_delivery(partial)
            if validate_delivery(facts_from(partial)) is not None:
                error = "INVALID_DELIVERY"
            else:
                legal_before = aggregate(scores()).legal_balls
                if legal_before >= max_balls:
                    error = "OVER_LIMIT_EXCEEDED"
                else:
                    position = derive_position(
                        legal_balls_before=legal_before,
                        max_sequence=max((x["delivery_sequence"] for x in deliveries), default=0),
                        legal=is_legal(is_wide=d["is_wide"], is_no_ball=d["is_no_ball"]),
                    )
                    deliveries.append(
                        {
                            **d,
                            "delivery_sequence": position.delivery_sequence,
                            "over_number": position.over_number,
                            "legal_ball_number": position.legal_ball_number,
                            "voided": False,
                        }
                    )
        elif step["op"] == "void_last":
            target = last_active()
            if target is None:
                error = "NOTHING_TO_VOID"
            else:
                target["voided"] = True
        elif step["op"] == "void_index":
            target = deliveries[step["index"]]
            if not target["voided"]:
                if target is last_active():
                    target["voided"] = True
                else:
                    error = "NOT_LAST_DELIVERY"
        else:  # pragma: no cover - guards against new ops in the vector file
            raise AssertionError(step["op"])
        errors.append(error)
        assert error == step.get("expect_error"), (seq["name"], step)
    return deliveries, errors


@pytest.mark.parametrize("seq", VECTORS["valid_sequences"], ids=lambda s: s["name"])
def test_valid_sequences(seq: dict[str, Any]) -> None:
    deliveries, _ = run_sequence(seq)
    expected = seq["expected"]
    totals = aggregate(
        DeliveryScore(
            runs_bat=d["runs_bat"],
            runs_extras=d["runs_extras"],
            is_wicket=d["is_wicket"],
            is_wide=d["is_wide"],
            is_no_ball=d["is_no_ball"],
            is_voided=d["voided"],
        )
        for d in deliveries
    )
    assert totals.total_runs == expected["total_runs"]
    assert totals.wickets == expected["wickets"]
    assert totals.legal_balls == expected["legal_balls"]
    assert len(deliveries) == len(expected["deliveries"])
    for actual, want in zip(deliveries, expected["deliveries"], strict=True):
        assert actual["delivery_sequence"] == want["delivery_sequence"]
        assert actual["over_number"] == want["over_number"]
        assert actual["legal_ball_number"] == want["legal_ball_number"]
        assert actual["voided"] == want.get("voided", False)
