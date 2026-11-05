"""Replays docs/scoring_test_vectors.json end-to-end through POST /sync/push."""

from __future__ import annotations

from typing import Any

import httpx
import pytest

from tests.helpers import API, MatchIds, event, push, register, seed_match, uid
from tests.vectors import VECTORS, full_delivery


def _payload(ids: MatchIds, partial: dict[str, Any]) -> dict[str, Any]:
    d = full_delivery(partial)
    dismissed = None
    if d["is_wicket"]:
        dismissed = ids.striker if d["dismissed"] == "STRIKER" else ids.non_striker
    return {
        "id": uid(),
        "innings_id": ids.innings,
        "bowler_id": ids.bowler,
        "striker_id": ids.striker,
        "non_striker_id": ids.non_striker,
        "runs_bat": d["runs_bat"],
        "runs_extras": d["runs_extras"],
        "is_wide": d["is_wide"],
        "is_no_ball": d["is_no_ball"],
        "is_bye": d["is_bye"],
        "is_leg_bye": d["is_leg_bye"],
        "is_wicket": d["is_wicket"],
        "dismissal_type": d["dismissal_type"],
        "dismissed_player_id": dismissed,
    }


@pytest.mark.parametrize("case", VECTORS["valid_deliveries"], ids=lambda c: c["name"])
async def test_valid_delivery_vectors_are_applied(
    client: httpx.AsyncClient, case: dict[str, Any]
) -> None:
    account = await register(client)
    ids = await seed_match(client, account, overs=1)
    [result] = await push(client, account, [event("DELIVERY", _payload(ids, case["delivery"]))])
    assert result["status"] == "APPLIED", result


@pytest.mark.parametrize("case", VECTORS["invalid_deliveries"], ids=lambda c: c["name"])
async def test_invalid_delivery_vectors_are_rejected(
    client: httpx.AsyncClient, case: dict[str, Any]
) -> None:
    account = await register(client)
    ids = await seed_match(client, account, overs=1)
    [result] = await push(client, account, [event("DELIVERY", _payload(ids, case["delivery"]))])
    assert result["status"] == "REJECTED", result
    assert result["error"]["code"] == case["expect_error"]
    assert result["error"]["message"]

    snapshot = (
        await client.get(f"{API}/matches/{ids.match}/snapshot", headers=account.headers)
    ).json()
    assert snapshot["deliveries"] == []
    assert snapshot["innings"][0]["total_runs"] == 0


@pytest.mark.parametrize("seq", VECTORS["valid_sequences"], ids=lambda s: s["name"])
async def test_valid_sequences_end_to_end(client: httpx.AsyncClient, seq: dict[str, Any]) -> None:
    account = await register(client)
    ids = await seed_match(client, account, overs=seq["overs_per_innings"])
    applied: list[dict[str, Any]] = []  # accepted adds, in add order: {"id", "voided"}

    def last_active() -> dict[str, Any] | None:
        active = [d for d in applied if not d["voided"]]
        return active[-1] if active else None

    for step in seq["steps"]:
        expected_error = step.get("expect_error")
        if step["op"] == "add":
            payload = _payload(ids, step["delivery"])
            [result] = await push(client, account, [event("DELIVERY", payload)])
            if expected_error:
                assert result["status"] == "REJECTED", (seq["name"], result)
                assert result["error"]["code"] == expected_error
            else:
                assert result["status"] == "APPLIED", (seq["name"], result)
                applied.append({"id": payload["id"], "voided": False})
        elif step["op"] == "void_last":
            target = last_active()
            if expected_error == "NOTHING_TO_VOID":
                # An app-level error: there is nothing to send to the server (it would answer
                # ENTITY_NOT_FOUND for an unknown delivery). Assert the same precondition.
                assert target is None
                continue
            assert target is not None
            [result] = await push(
                client, account, [event("DELIVERY", {"id": target["id"]}, action="VOID")]
            )
            assert result["status"] == "APPLIED", (seq["name"], result)
            target["voided"] = True
        elif step["op"] == "void_index":
            target = applied[step["index"]]
            [result] = await push(
                client, account, [event("DELIVERY", {"id": target["id"]}, action="VOID")]
            )
            if expected_error:
                assert result["status"] == "REJECTED", (seq["name"], result)
                assert result["error"]["code"] == expected_error
            else:
                assert result["status"] == "APPLIED"
                target["voided"] = True

    expected = seq["expected"]
    snapshot = (
        await client.get(f"{API}/matches/{ids.match}/snapshot", headers=account.headers)
    ).json()
    innings = snapshot["innings"][0]
    assert innings["total_runs"] == expected["total_runs"]
    assert innings["wickets"] == expected["wickets"]
    assert innings["legal_balls"] == expected["legal_balls"]

    rows = sorted(snapshot["deliveries"], key=lambda d: d["delivery_sequence"])
    assert len(rows) == len(expected["deliveries"])
    for row, want in zip(rows, expected["deliveries"], strict=True):
        assert row["delivery_sequence"] == want["delivery_sequence"]
        assert row["over_number"] == want["over_number"]
        assert row["legal_ball_number"] == want["legal_ball_number"]
        assert row["is_voided"] == want.get("voided", False)
