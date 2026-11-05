"""Per-entity behaviour and error codes of POST /sync/push (API_CONTRACT §5.3, SCORING_RULES)."""

from __future__ import annotations

from typing import Any

import httpx
import pytest

from tests.helpers import (
    API,
    Account,
    MatchIds,
    delivery_payload,
    event,
    iso,
    player_payload,
    push,
    push_ok,
    register,
    seed_match,
    uid,
)


async def one(client: httpx.AsyncClient, account: Account, ev: dict[str, Any]) -> dict[str, Any]:
    [result] = await push(client, account, [ev])
    return result


async def applied(client: httpx.AsyncClient, account: Account, ev: dict[str, Any]) -> None:
    result = await one(client, account, ev)
    assert result["status"] == "APPLIED", result


async def rejected(
    client: httpx.AsyncClient, account: Account, ev: dict[str, Any], code: str
) -> dict[str, Any]:
    result = await one(client, account, ev)
    assert result["status"] == "REJECTED", result
    assert result["error"]["code"] == code, result
    assert result["error"]["message"]
    return result


async def snapshot(client: httpx.AsyncClient, account: Account, match_id: str) -> dict[str, Any]:
    response = await client.get(f"{API}/matches/{match_id}/snapshot", headers=account.headers)
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


async def add_delivery(
    client: httpx.AsyncClient, account: Account, ids: MatchIds, **overrides: Any
) -> dict[str, Any]:
    payload = delivery_payload(ids, **overrides)
    await applied(client, account, event("DELIVERY", payload))
    return payload


def delivery_by_id(snap: dict[str, Any], delivery_id: str) -> dict[str, Any]:
    [found] = [d for d in snap["deliveries"] if d["id"] == delivery_id]
    return found


def wicket_detection_payload(match_id: str, **overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": uid(),
        "match_id": match_id,
        "wicket_family": "BUCKET",
        "bounding_box": {"x": 0.4, "y": 0.3, "width": 0.1, "height": 0.3},
        "target_polygon": [
            {"x": 0.4, "y": 0.3},
            {"x": 0.5, "y": 0.3},
            {"x": 0.5, "y": 0.6},
            {"x": 0.4, "y": 0.6},
        ],
        "object_confidence": 0.9,
        "temporal_stability": 0.8,
        "context_confidence": 0.7,
        "final_confidence": 0.85,
        "model_version": "mock-wicket-1",
    }
    payload.update(overrides)
    return payload


def scene_scan_payload(match_id: str, **overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": uid(),
        "match_id": match_id,
        "camera_device_model": "Pixel 7",
        "capture_fps": 30,
        "scan_duration_ms": 4200,
        "ground_plane": {"normal": [0, 1, 0]},
        "overall_confidence": 0.9,
        "model_version": "mock-scene-1",
    }
    payload.update(overrides)
    return payload


# ============================================================================ players & teams


async def test_player_is_created_and_then_updated_in_place(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    pid = uid()
    await applied(client, account, event("PLAYER", player_payload(pid, "  Ravi  ")))
    await applied(
        client,
        account,
        event("PLAYER", player_payload(pid, "Ravi K", batting_hand="LEFT", declared_height_cm=178)),
    )
    response = await client.get(f"{API}/players", headers=account.headers)
    players = {p["id"]: p for p in response.json()["items"]}
    assert players[pid]["display_name"] == "Ravi K"
    assert players[pid]["batting_hand"] == "LEFT"
    assert players[pid]["declared_height_cm"] == 178
    assert response.json()["total"] == 6  # the 5 seeded players + Ravi
    assert ids.striker in players


async def test_player_defaults_and_trimming(client: httpx.AsyncClient) -> None:
    account = await register(client)
    pid = uid()
    await applied(client, account, event("PLAYER", {"id": pid, "display_name": "  Ravi  "}))
    items = (await client.get(f"{API}/players", headers=account.headers)).json()["items"]
    assert items[0]["display_name"] == "Ravi"
    assert items[0]["batting_hand"] == "UNKNOWN"
    assert items[0]["declared_height_cm"] is None


@pytest.mark.parametrize(
    "extra",
    [
        {"display_name": ""},
        {"display_name": "   "},
        {"display_name": "x" * 101},
        {"declared_height_cm": 99},
        {"declared_height_cm": 231},
        {"declared_height_cm": 170.5},
        {"batting_hand": "AMBIDEXTROUS"},
        {"nickname": "Rav"},
    ],
)
async def test_player_payload_validation(client: httpx.AsyncClient, extra: dict[str, Any]) -> None:
    account = await register(client)
    payload = {"id": uid(), "display_name": "Ravi", **extra}
    await rejected(client, account, event("PLAYER", payload), "INVALID_PAYLOAD")


async def test_team_is_created_and_renamed(client: httpx.AsyncClient) -> None:
    account = await register(client)
    tid = uid()
    await applied(client, account, event("TEAM", {"id": tid, "name": "Reds"}))
    await applied(client, account, event("TEAM", {"id": tid, "name": "Crimson"}))
    items = (await client.get(f"{API}/teams", headers=account.headers)).json()["items"]
    assert [(t["id"], t["name"]) for t in items] == [(tid, "Crimson")]


@pytest.mark.parametrize("name", ["", "  ", "x" * 101])
async def test_team_name_validation(client: httpx.AsyncClient, name: str) -> None:
    account = await register(client)
    await rejected(client, account, event("TEAM", {"id": uid(), "name": name}), "INVALID_PAYLOAD")


async def test_players_and_teams_of_another_user_cannot_be_modified(
    client: httpx.AsyncClient,
) -> None:
    owner = await register(client)
    intruder = await register(client)
    pid, tid = uid(), uid()
    await applied(client, owner, event("PLAYER", player_payload(pid, "Mine")))
    await applied(client, owner, event("TEAM", {"id": tid, "name": "Mine"}))
    await rejected(client, intruder, event("PLAYER", player_payload(pid, "Stolen")), "FORBIDDEN")
    await rejected(client, intruder, event("TEAM", {"id": tid, "name": "Stolen"}), "FORBIDDEN")
    assert (await client.get(f"{API}/players", headers=owner.headers)).json()["items"][0][
        "display_name"
    ] == "Mine"
    assert (await client.get(f"{API}/players", headers=intruder.headers)).json()["total"] == 0


# ============================================================================ matches


def match_payload(ids: MatchIds, **overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": ids.match,
        "team_a_id": ids.team_a,
        "team_b_id": ids.team_b,
        "status": "LIVE",
        "overs_per_innings": 2,
        "match_name": "Sunday finals",
    }
    payload.update(overrides)
    return payload


async def test_match_defaults(client: httpx.AsyncClient) -> None:
    account = await register(client)
    team_a, team_b, match = uid(), uid(), uid()
    await push_ok(
        client,
        account,
        [
            event("TEAM", {"id": team_a, "name": "A"}),
            event("TEAM", {"id": team_b, "name": "B"}),
            event("MATCH", {"id": match, "team_a_id": team_a, "team_b_id": team_b}),
        ],
    )
    body = (await snapshot(client, account, match))["match"]
    assert body["status"] == "DRAFT"
    assert body["overs_per_innings"] == 6
    assert body["local_rules_profile"] == "CASUAL_GULLY"
    assert body["winner_team_id"] is None


async def test_match_requires_existing_owned_teams(client: httpx.AsyncClient) -> None:
    account = await register(client)
    other = await register(client)
    mine, theirs = uid(), uid()
    await applied(client, account, event("TEAM", {"id": mine, "name": "Mine"}))
    await applied(client, other, event("TEAM", {"id": theirs, "name": "Theirs"}))

    payload = {"id": uid(), "team_a_id": mine, "team_b_id": uid()}
    await rejected(client, account, event("MATCH", payload), "PARENT_NOT_FOUND")
    payload = {"id": uid(), "team_a_id": mine, "team_b_id": theirs}
    await rejected(client, account, event("MATCH", payload), "FORBIDDEN")


async def test_match_teams_must_differ(client: httpx.AsyncClient) -> None:
    account = await register(client)
    team = uid()
    await applied(client, account, event("TEAM", {"id": team, "name": "A"}))
    payload = {"id": uid(), "team_a_id": team, "team_b_id": team}
    await rejected(client, account, event("MATCH", payload), "INVALID_PAYLOAD")


@pytest.mark.parametrize(
    "extra",
    [
        {"overs_per_innings": 0},
        {"overs_per_innings": 51},
        {"status": "PAUSED"},
        {"scheduled_at": "2026-10-10T10:00:00"},  # naive timestamps are rejected
        {"match_name": "x" * 151},
    ],
)
async def test_match_payload_validation(client: httpx.AsyncClient, extra: dict[str, Any]) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await rejected(client, account, event("MATCH", match_payload(ids, **extra)), "INVALID_PAYLOAD")


async def test_match_winner_must_be_a_match_team(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    stranger = uid()
    await applied(client, account, event("TEAM", {"id": stranger, "name": "Stranger"}))
    await rejected(
        client,
        account,
        event("MATCH", match_payload(ids, status="COMPLETED", winner_team_id=stranger)),
        "INVALID_REFERENCE",
    )
    await applied(
        client,
        account,
        event(
            "MATCH",
            match_payload(
                ids, status="COMPLETED", winner_team_id=ids.team_a, result_summary="Reds won by 4"
            ),
        ),
    )
    body = (await snapshot(client, account, ids.match))["match"]
    assert (body["status"], body["winner_team_id"], body["result_summary"]) == (
        "COMPLETED",
        ids.team_a,
        "Reds won by 4",
    )


async def test_match_update_keeps_creation_data_and_rejects_team_changes(
    client: httpx.AsyncClient,
) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    before = (await snapshot(client, account, ids.match))["match"]

    await applied(client, account, event("MATCH", match_payload(ids, match_name="Renamed")))
    after = (await snapshot(client, account, ids.match))["match"]
    assert after["match_name"] == "Renamed"
    assert after["created_at"] == before["created_at"]

    swapped = match_payload(ids, team_a_id=ids.team_b, team_b_id=ids.team_a)
    await rejected(client, account, event("MATCH", swapped), "INVALID_STATE")


@pytest.mark.parametrize("terminal", ["COMPLETED", "ABANDONED"])
async def test_terminal_match_cannot_change_status(
    client: httpx.AsyncClient, terminal: str
) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await applied(client, account, event("MATCH", match_payload(ids, status=terminal)))
    # Re-sending the same status (e.g. a metadata edit) is fine ...
    await applied(
        client, account, event("MATCH", match_payload(ids, status=terminal, match_name="Edit"))
    )
    # ... moving back to a live state is not.
    await rejected(
        client, account, event("MATCH", match_payload(ids, status="LIVE")), "INVALID_STATE"
    )


async def test_match_of_another_user_cannot_be_updated(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner, with_innings=False)
    await rejected(client, intruder, event("MATCH", match_payload(ids)), "FORBIDDEN")


async def test_delete_match_cascades_to_everything_below_it(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    delivery = await add_delivery(client, account, ids, runs_bat=4)
    await applied(
        client,
        account,
        event(
            "DELIVERY_DECISION",
            {
                "id": uid(),
                "delivery_id": delivery["id"],
                "decision_type": "EDGE",
                "decision_status": "AUTO_CALL",
                "decision_source": "AI_ASSIST",
            },
        ),
    )
    await applied(client, account, event("SCENE_SCAN", scene_scan_payload(ids.match)))
    await applied(client, account, event("MATCH_RULES", {"match_id": ids.match}))

    await applied(client, account, event("MATCH", {"id": ids.match}, action="DELETE"))

    response = await client.get(f"{API}/matches/{ids.match}/snapshot", headers=account.headers)
    assert response.status_code == 404
    assert (await client.get(f"{API}/matches", headers=account.headers)).json()["total"] == 0
    # The roster (players and teams) survives: it is reusable across matches.
    assert (await client.get(f"{API}/players", headers=account.headers)).json()["total"] == 5
    assert (await client.get(f"{API}/teams", headers=account.headers)).json()["total"] == 2


async def test_delete_match_is_idempotent_and_owner_scoped(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner, with_innings=False)

    await rejected(
        client, intruder, event("MATCH", {"id": ids.match}, action="DELETE"), "FORBIDDEN"
    )
    await applied(client, owner, event("MATCH", {"id": uid()}, action="DELETE"))  # unknown id
    await applied(client, owner, event("MATCH", {"id": ids.match}, action="DELETE"))
    await applied(client, owner, event("MATCH", {"id": ids.match}, action="DELETE"))  # again


async def test_events_after_a_delete_in_the_same_batch_do_not_see_the_deleted_rows(
    client: httpx.AsyncClient,
) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    results = await push(
        client,
        account,
        [
            event("MATCH", {"id": ids.match}, action="DELETE"),
            event("DELIVERY", delivery_payload(ids)),
            event(
                "TOSS",
                {"id": uid(), "match_id": ids.match, "call_choice": "HEADS", "result": "TAILS"},
            ),
        ],
    )
    assert [r["status"] for r in results] == ["APPLIED", "REJECTED", "REJECTED"]
    assert results[1]["error"]["code"] == "PARENT_NOT_FOUND"
    assert results[2]["error"]["code"] == "PARENT_NOT_FOUND"


# ============================================================================ match players


async def test_match_player_upsert_updates_the_same_row(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await applied(
        client,
        account,
        event(
            "MATCH_PLAYER",
            {
                "match_id": ids.match,
                "player_id": ids.striker,
                "team_id": ids.team_a,
                "batting_order": 1,
                "is_captain": True,
                "batting_hand": "LEFT",
                "declared_height_cm": 180,
            },
        ),
    )
    snap = await snapshot(client, account, ids.match)
    assert len(snap["match_players"]) == 5
    [row] = [mp for mp in snap["match_players"] if mp["player_id"] == ids.striker]
    assert (
        row["batting_order"],
        row["is_captain"],
        row["batting_hand"],
        row["declared_height_cm"],
    ) == (
        1,
        True,
        "LEFT",
        180,
    )
    assert row["is_wicketkeeper"] is False


async def test_match_player_references_are_checked(client: httpx.AsyncClient) -> None:
    account = await register(client)
    other = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    foreign_player = uid()
    await applied(client, other, event("PLAYER", player_payload(foreign_player, "Foreign")))
    stranger_team = uid()
    await applied(client, account, event("TEAM", {"id": stranger_team, "name": "Stranger"}))

    def mp(**kw: Any) -> dict[str, Any]:
        base = {"match_id": ids.match, "player_id": ids.striker, "team_id": ids.team_a}
        base.update(kw)
        return event("MATCH_PLAYER", base)

    await rejected(client, account, mp(match_id=uid()), "PARENT_NOT_FOUND")
    await rejected(client, account, mp(player_id=uid()), "PARENT_NOT_FOUND")
    await rejected(client, account, mp(player_id=foreign_player), "FORBIDDEN")
    await rejected(client, account, mp(team_id=stranger_team), "INVALID_REFERENCE")
    await rejected(client, other, mp(), "FORBIDDEN")


@pytest.mark.parametrize(
    "extra", [{"batting_order": 0}, {"batting_order": 31}, {"is_captain": "yes"}]
)
async def test_match_player_payload_validation(
    client: httpx.AsyncClient, extra: dict[str, Any]
) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    payload = {"match_id": ids.match, "player_id": ids.striker, "team_id": ids.team_a, **extra}
    await rejected(client, account, event("MATCH_PLAYER", payload), "INVALID_PAYLOAD")


# ============================================================================ match rules


async def test_match_rules_defaults_and_update(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    assert (await snapshot(client, account, ids.match))["rules"] is None

    await applied(client, account, event("MATCH_RULES", {"match_id": ids.match}))
    rules = (await snapshot(client, account, ids.match))["rules"]
    assert rules["wide_enabled"] is True
    assert rules["front_foot_no_ball_enabled"] is False
    assert rules["lateral_reach_multiplier"] == pytest.approx(0.6)
    assert rules["max_bouncers_per_over"] is None

    await applied(
        client,
        account,
        event(
            "MATCH_RULES",
            {
                "match_id": ids.match,
                "wide_enabled": False,
                "max_bouncers_per_over": 2,
                "lateral_reach_multiplier": 0.9,
            },
        ),
    )
    rules = (await snapshot(client, account, ids.match))["rules"]
    assert rules["wide_enabled"] is False
    assert rules["max_bouncers_per_over"] == 2
    assert rules["lateral_reach_multiplier"] == pytest.approx(0.9)


@pytest.mark.parametrize(
    "extra",
    [
        {"lateral_reach_multiplier": 0.19},
        {"lateral_reach_multiplier": 1.51},
        {"max_bouncers_per_over": 7},
        {"max_bouncers_per_over": -1},
        {"wide_enabled": "true"},
    ],
)
async def test_match_rules_payload_validation(
    client: httpx.AsyncClient, extra: dict[str, Any]
) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await rejected(
        client, account, event("MATCH_RULES", {"match_id": ids.match, **extra}), "INVALID_PAYLOAD"
    )


async def test_match_rules_need_an_owned_match(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner, with_innings=False)
    await rejected(client, owner, event("MATCH_RULES", {"match_id": uid()}), "PARENT_NOT_FOUND")
    await rejected(client, intruder, event("MATCH_RULES", {"match_id": ids.match}), "FORBIDDEN")


# ============================================================================ scene scans


async def test_scene_scan_create_and_update(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    payload = scene_scan_payload(ids.match, created_at="2026-10-10T08:00:00Z")
    await applied(client, account, event("SCENE_SCAN", payload))
    await applied(
        client,
        account,
        event("SCENE_SCAN", {**payload, "overall_confidence": 0.5, "pitch_direction": {"yaw": 12}}),
    )
    [scan] = (await snapshot(client, account, ids.match))["scene_scans"]
    assert scan["overall_confidence"] == 0.5
    assert scan["pitch_direction"] == {"yaw": 12}
    assert scan["ground_plane"] == {"normal": [0, 1, 0]}
    assert scan["created_at"].startswith("2026-10-10T08:00:00")


async def test_scene_scan_cannot_move_between_matches(client: httpx.AsyncClient) -> None:
    account = await register(client)
    first = await seed_match(client, account, with_innings=False)
    second = await seed_match(client, account, with_innings=False)
    payload = scene_scan_payload(first.match)
    await applied(client, account, event("SCENE_SCAN", payload))
    await rejected(
        client, account, event("SCENE_SCAN", {**payload, "match_id": second.match}), "INVALID_STATE"
    )


@pytest.mark.parametrize(
    "extra",
    [
        {"overall_confidence": 1.1},
        {"scan_duration_ms": -1},
        {"scan_duration_ms": 120_001},
        {"capture_fps": 0},
        {"model_version": ""},
        {"ground_plane": {"blob": "x" * 70_000}},  # over the 64 KiB JSON limit
        {"ground_plane": [1, 2, 3]},
    ],
)
async def test_scene_scan_payload_validation(
    client: httpx.AsyncClient, extra: dict[str, Any]
) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await rejected(
        client,
        account,
        event("SCENE_SCAN", scene_scan_payload(ids.match, **extra)),
        "INVALID_PAYLOAD",
    )


async def test_scene_scan_needs_an_owned_match(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner, with_innings=False)
    await rejected(
        client, owner, event("SCENE_SCAN", scene_scan_payload(uid())), "PARENT_NOT_FOUND"
    )
    await rejected(
        client, intruder, event("SCENE_SCAN", scene_scan_payload(ids.match)), "FORBIDDEN"
    )


# ============================================================================ wicket detections


async def test_wicket_detection_create_update_and_link_to_scan(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    scan = scene_scan_payload(ids.match)
    await applied(client, account, event("SCENE_SCAN", scan))
    payload = wicket_detection_payload(ids.match, scene_scan_id=scan["id"])
    await applied(client, account, event("WICKET_DETECTION", payload))
    await applied(
        client,
        account,
        event("WICKET_DETECTION", {**payload, "is_active": False, "wicket_family": "CHAIR"}),
    )
    [row] = (await snapshot(client, account, ids.match))["wicket_detections"]
    assert row["scene_scan_id"] == scan["id"]
    assert row["is_active"] is False
    assert row["wicket_family"] == "CHAIR"
    assert row["bounding_box"] == payload["bounding_box"]
    assert len(row["target_polygon"]) == 4
    assert row["final_confidence"] == pytest.approx(0.85)


async def test_wicket_detection_references_are_checked(client: httpx.AsyncClient) -> None:
    account = await register(client)
    first = await seed_match(client, account, with_innings=False)
    second = await seed_match(client, account, with_innings=False)
    scan_of_second = scene_scan_payload(second.match)
    await applied(client, account, event("SCENE_SCAN", scan_of_second))

    await rejected(
        client,
        account,
        event("WICKET_DETECTION", wicket_detection_payload(first.match, scene_scan_id=uid())),
        "PARENT_NOT_FOUND",
    )
    await rejected(
        client,
        account,
        event(
            "WICKET_DETECTION",
            wicket_detection_payload(first.match, scene_scan_id=scan_of_second["id"]),
        ),
        "INVALID_REFERENCE",
    )
    await rejected(
        client,
        account,
        event("WICKET_DETECTION", wicket_detection_payload(uid())),
        "PARENT_NOT_FOUND",
    )

    payload = wicket_detection_payload(first.match)
    await applied(client, account, event("WICKET_DETECTION", payload))
    await rejected(
        client,
        account,
        event("WICKET_DETECTION", {**payload, "match_id": second.match}),
        "INVALID_STATE",
    )


@pytest.mark.parametrize(
    "extra",
    [
        {"wicket_family": "STUMPS"},
        {"target_polygon": [{"x": 0.1, "y": 0.1}, {"x": 0.2, "y": 0.2}]},  # < 3 points
        {"target_polygon": [{"x": 0.1, "y": 0.1}] * 33},  # > 32 points
        {"target_polygon": [{"x": 1.5, "y": 0.1}] * 3},
        {"bounding_box": {"x": 0.1, "y": 0.1, "width": 0.1}},
        {"final_confidence": -0.1},
    ],
)
async def test_wicket_detection_payload_validation(
    client: httpx.AsyncClient, extra: dict[str, Any]
) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await rejected(
        client,
        account,
        event("WICKET_DETECTION", wicket_detection_payload(ids.match, **extra)),
        "INVALID_PAYLOAD",
    )


async def test_wicket_detection_of_another_user_is_forbidden(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner, with_innings=False)
    await rejected(
        client,
        intruder,
        event("WICKET_DETECTION", wicket_detection_payload(ids.match)),
        "FORBIDDEN",
    )


# ============================================================================ toss


def toss_payload(ids: MatchIds, **overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": uid(),
        "match_id": ids.match,
        "call_choice": "HEADS",
        "result": "TAILS",
        "winner_team_id": ids.team_b,
        "winner_decision": "BAT",
    }
    payload.update(overrides)
    return payload


async def test_toss_create_and_update(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    payload = toss_payload(ids, called_by_player_id=ids.striker)
    await applied(client, account, event("TOSS", payload))
    await applied(client, account, event("TOSS", {**payload, "winner_decision": "BOWL"}))
    toss = (await snapshot(client, account, ids.match))["toss"]
    assert toss["id"] == payload["id"]
    assert toss["winner_decision"] == "BOWL"
    assert toss["called_by_player_id"] == ids.striker
    assert toss["winner_team_id"] == ids.team_b


async def test_a_match_has_exactly_one_toss(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await applied(client, account, event("TOSS", toss_payload(ids)))
    await rejected(client, account, event("TOSS", toss_payload(ids)), "INVALID_STATE")


async def test_toss_cannot_move_to_another_match(client: httpx.AsyncClient) -> None:
    account = await register(client)
    first = await seed_match(client, account, with_innings=False)
    second = await seed_match(client, account, with_innings=False)
    payload = toss_payload(first)
    await applied(client, account, event("TOSS", payload))
    await rejected(
        client, account, event("TOSS", {**payload, "match_id": second.match}), "INVALID_STATE"
    )


async def test_toss_references_are_checked(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    loose_player, stranger_team = uid(), uid()
    await applied(client, account, event("PLAYER", player_payload(loose_player, "Not in match")))
    await applied(client, account, event("TEAM", {"id": stranger_team, "name": "Stranger"}))

    await rejected(
        client,
        account,
        event("TOSS", toss_payload(ids, called_by_player_id=loose_player)),
        "INVALID_REFERENCE",
    )
    await rejected(
        client,
        account,
        event("TOSS", toss_payload(ids, winner_team_id=stranger_team)),
        "INVALID_REFERENCE",
    )
    await rejected(
        client, account, event("TOSS", toss_payload(ids, match_id=uid())), "PARENT_NOT_FOUND"
    )
    # None of the failed attempts may have left a toss behind.
    assert (await snapshot(client, account, ids.match))["toss"] is None


@pytest.mark.parametrize(
    "extra",
    [{"call_choice": "EDGE"}, {"result": None}, {"winner_decision": "FIELD"}, {"unexpected": 1}],
)
async def test_toss_payload_validation(client: httpx.AsyncClient, extra: dict[str, Any]) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await rejected(client, account, event("TOSS", toss_payload(ids, **extra)), "INVALID_PAYLOAD")


async def test_toss_of_another_user_is_forbidden(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner, with_innings=False)
    await rejected(client, intruder, event("TOSS", toss_payload(ids)), "FORBIDDEN")


# ============================================================================ innings


def innings_payload(ids: MatchIds, **overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": uid(),
        "match_id": ids.match,
        "innings_number": 2,
        "batting_team_id": ids.team_b,
        "bowling_team_id": ids.team_a,
        "started_at": iso(),
    }
    payload.update(overrides)
    return payload


async def test_innings_create_starts_at_zero_and_can_be_closed(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    snap = await snapshot(client, account, ids.match)
    [first] = snap["innings"]
    assert (first["total_runs"], first["wickets"], first["legal_balls"]) == (0, 0, 0)
    assert first["ended_at"] is None

    payload = innings_payload(ids)
    await applied(client, account, event("INNINGS", payload))
    await applied(client, account, event("INNINGS", {**payload, "ended_at": iso()}))
    snap = await snapshot(client, account, ids.match)
    assert [i["innings_number"] for i in snap["innings"]] == [1, 2]
    assert snap["innings"][1]["ended_at"] is not None


async def test_innings_number_is_unique_per_match(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    await rejected(
        client, account, event("INNINGS", innings_payload(ids, innings_number=1)), "INVALID_STATE"
    )


async def test_innings_identity_fields_are_immutable(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    other = await seed_match(client, account)
    base = {
        "id": ids.innings,
        "match_id": ids.match,
        "innings_number": 1,
        "batting_team_id": ids.team_a,
        "bowling_team_id": ids.team_b,
        "started_at": iso(),
    }
    await rejected(
        client, account, event("INNINGS", {**base, "innings_number": 2}), "INVALID_STATE"
    )
    await rejected(
        client, account, event("INNINGS", {**base, "match_id": other.match}), "INVALID_REFERENCE"
    )
    swapped = {**base, "batting_team_id": ids.team_b, "bowling_team_id": ids.team_a}
    await rejected(client, account, event("INNINGS", swapped), "INVALID_STATE")


async def test_innings_teams_must_belong_to_the_match(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    stranger = uid()
    await applied(client, account, event("TEAM", {"id": stranger, "name": "Stranger"}))
    await rejected(
        client,
        account,
        event("INNINGS", innings_payload(ids, innings_number=1, batting_team_id=stranger)),
        "INVALID_REFERENCE",
    )


@pytest.mark.parametrize(
    "extra",
    [
        {"innings_number": 0},
        {"innings_number": 5},
        {"ended_at": "2000-01-01T00:00:00Z"},  # before started_at
        {"started_at": None},
    ],
)
async def test_innings_payload_validation(client: httpx.AsyncClient, extra: dict[str, Any]) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await rejected(
        client, account, event("INNINGS", innings_payload(ids, **extra)), "INVALID_PAYLOAD"
    )


async def test_innings_batting_and_bowling_team_must_differ(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    await rejected(
        client,
        account,
        event(
            "INNINGS", innings_payload(ids, batting_team_id=ids.team_a, bowling_team_id=ids.team_a)
        ),
        "INVALID_PAYLOAD",
    )


async def test_innings_of_another_user_is_forbidden(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner, with_innings=False)
    await rejected(client, intruder, event("INNINGS", innings_payload(ids)), "FORBIDDEN")


# ============================================================================ deliveries


async def test_derived_fields_and_innings_totals(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    first = await add_delivery(client, account, ids, runs_bat=4)
    wide = await add_delivery(client, account, ids, is_wide=True, runs_extras=1)
    wicket = await add_delivery(
        client,
        account,
        ids,
        is_wicket=True,
        dismissal_type="BOWLED",
        dismissed_player_id=ids.striker,
    )
    snap = await snapshot(client, account, ids.match)

    d1, d2, d3 = (delivery_by_id(snap, d["id"]) for d in (first, wide, wicket))
    assert (d1["delivery_sequence"], d1["over_number"], d1["legal_ball_number"]) == (1, 0, 1)
    assert (d2["delivery_sequence"], d2["over_number"], d2["legal_ball_number"]) == (2, 0, None)
    assert (d3["delivery_sequence"], d3["over_number"], d3["legal_ball_number"]) == (3, 0, 2)
    assert d3["dismissal_type"] == "BOWLED"
    assert d3["dismissed_player_id"] == ids.striker
    assert [d["delivery_sequence"] for d in snap["deliveries"]] == [1, 2, 3]

    [innings] = snap["innings"]
    assert (innings["total_runs"], innings["wickets"], innings["legal_balls"]) == (5, 1, 2)


async def test_over_number_rolls_over_after_six_legal_balls(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, overs=2)
    for _ in range(6):
        await add_delivery(client, account, ids)
    wide = await add_delivery(client, account, ids, is_wide=True, runs_extras=1)
    seventh = await add_delivery(client, account, ids, runs_bat=1)
    snap = await snapshot(client, account, ids.match)
    assert [d["legal_ball_number"] for d in snap["deliveries"]] == [1, 2, 3, 4, 5, 6, None, 1]
    assert delivery_by_id(snap, wide["id"])["over_number"] == 1
    assert delivery_by_id(snap, seventh["id"])["over_number"] == 1
    assert snap["innings"][0]["legal_balls"] == 7


async def test_over_limit_is_enforced_for_every_kind_of_delivery(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, overs=1)
    for _ in range(6):
        await add_delivery(client, account, ids)
    for overrides in (
        {},
        {"is_wide": True, "runs_extras": 1},
        {"is_no_ball": True, "runs_extras": 1},
    ):
        await rejected(
            client,
            account,
            event("DELIVERY", delivery_payload(ids, **overrides)),
            "OVER_LIMIT_EXCEEDED",
        )
    assert (await snapshot(client, account, ids.match))["innings"][0]["legal_balls"] == 6


async def test_innings_that_has_ended_accepts_no_more_deliveries(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    await add_delivery(client, account, ids)
    await applied(
        client,
        account,
        event(
            "INNINGS",
            {
                "id": ids.innings,
                "match_id": ids.match,
                "innings_number": 1,
                "batting_team_id": ids.team_a,
                "bowling_team_id": ids.team_b,
                "started_at": iso(),
                "ended_at": iso(),
            },
        ),
    )
    await rejected(client, account, event("DELIVERY", delivery_payload(ids)), "INNINGS_CLOSED")


async def test_validation_order_is_rules_then_roster_then_closed_then_limit(
    client: httpx.AsyncClient,
) -> None:
    account = await register(client)
    ids = await seed_match(client, account, overs=1)
    for _ in range(6):
        await add_delivery(client, account, ids)  # innings is now full

    # Rule violation beats everything below it.
    bad_rules = delivery_payload(ids, runs_bat=8, bowler_id=uid())
    await rejected(client, account, event("DELIVERY", bad_rules), "INVALID_DELIVERY")
    # Then roster membership.
    bad_roster = delivery_payload(ids, bowler_id=uid())
    await rejected(client, account, event("DELIVERY", bad_roster), "INVALID_REFERENCE")
    # Then a closed innings ...
    await applied(
        client,
        account,
        event(
            "INNINGS",
            {
                "id": ids.innings,
                "match_id": ids.match,
                "innings_number": 1,
                "batting_team_id": ids.team_a,
                "bowling_team_id": ids.team_b,
                "started_at": iso(),
                "ended_at": iso(),
            },
        ),
    )
    await rejected(client, account, event("DELIVERY", delivery_payload(ids)), "INNINGS_CLOSED")
    # ... and the over limit only applies to an open innings (covered above).


@pytest.mark.parametrize(
    "overrides",
    [
        {"runs_bat": 8},
        {"runs_bat": -1},
        {"runs_extras": 11},
        {"is_wide": True, "is_no_ball": True, "runs_extras": 1},
        {"is_wicket": True},  # no dismissal type
        {"striker_id": "same-as-non-striker"},
    ],
)
async def test_rule_violations_are_invalid_delivery_not_invalid_payload(
    client: httpx.AsyncClient, overrides: dict[str, Any]
) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    if overrides.get("striker_id") == "same-as-non-striker":
        overrides = {"striker_id": ids.non_striker}
    await rejected(
        client, account, event("DELIVERY", delivery_payload(ids, **overrides)), "INVALID_DELIVERY"
    )
    assert (await snapshot(client, account, ids.match))["deliveries"] == []


@pytest.mark.parametrize(
    "overrides",
    [
        {"runs_bat": "4"},
        {"runs_bat": 1.5},
        {"is_wide": 1},
        {"dismissed_player_id": "11111111-1111-4111-8111-111111111111"},  # not a wicket
        {"speed_kmph": 251},
        {"speed_confidence": 1.5},
        {"dismissal_type": "OBSTRUCTING_THE_FIELD", "is_wicket": True},
        {"mystery": 1},
    ],
)
async def test_delivery_schema_violations_are_invalid_payload(
    client: httpx.AsyncClient, overrides: dict[str, Any]
) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    await rejected(
        client, account, event("DELIVERY", delivery_payload(ids, **overrides)), "INVALID_PAYLOAD"
    )


async def test_delivery_roster_references(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    outsider = uid()
    await applied(client, account, event("PLAYER", player_payload(outsider, "Not in this match")))

    for field in ("bowler_id", "striker_id", "non_striker_id"):
        await rejected(
            client,
            account,
            event("DELIVERY", delivery_payload(ids, **{field: outsider})),
            "INVALID_REFERENCE",
        )
    await rejected(
        client,
        account,
        event("DELIVERY", delivery_payload(ids, bowler_id=uid())),
        "INVALID_REFERENCE",
    )
    # A dismissed player has to be on the roster as well.
    await rejected(
        client,
        account,
        event(
            "DELIVERY",
            delivery_payload(
                ids,
                is_wicket=True,
                dismissal_type="RUN_OUT",
                non_striker_id=outsider,
                dismissed_player_id=outsider,
            ),
        ),
        "INVALID_REFERENCE",
    )


async def test_delivery_without_a_non_striker_is_allowed(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    await add_delivery(client, account, ids, non_striker_id=None, runs_bat=2)
    [d] = (await snapshot(client, account, ids.match))["deliveries"]
    assert d["non_striker_id"] is None


async def test_run_out_may_dismiss_the_non_striker(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    sent = await add_delivery(
        client,
        account,
        ids,
        is_wicket=True,
        dismissal_type="RUN_OUT",
        dismissed_player_id=ids.non_striker,
        runs_bat=1,
    )
    snap = await snapshot(client, account, ids.match)
    assert delivery_by_id(snap, sent["id"])["dismissed_player_id"] == ids.non_striker
    assert snap["innings"][0]["wickets"] == 1


async def test_delivery_parent_must_exist_and_be_owned(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner)
    await rejected(
        client,
        owner,
        event("DELIVERY", delivery_payload(ids, innings_id=uid())),
        "PARENT_NOT_FOUND",
    )
    await rejected(client, intruder, event("DELIVERY", delivery_payload(ids)), "FORBIDDEN")
    assert (await snapshot(client, owner, ids.match))["deliveries"] == []


async def test_delivery_wicket_detection_link(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    other = await seed_match(client, account)
    here = wicket_detection_payload(ids.match)
    there = wicket_detection_payload(other.match)
    await push_ok(
        client, account, [event("WICKET_DETECTION", here), event("WICKET_DETECTION", there)]
    )

    await rejected(
        client,
        account,
        event("DELIVERY", delivery_payload(ids, wicket_detection_id=uid())),
        "PARENT_NOT_FOUND",
    )
    await rejected(
        client,
        account,
        event("DELIVERY", delivery_payload(ids, wicket_detection_id=there["id"])),
        "INVALID_REFERENCE",
    )
    sent = await add_delivery(client, account, ids, wicket_detection_id=here["id"], speed_kmph=61.5)
    d = delivery_by_id(await snapshot(client, account, ids.match), sent["id"])
    assert d["wicket_detection_id"] == here["id"]
    assert d["speed_kmph"] == pytest.approx(61.5)


async def test_delivery_is_create_only(client: httpx.AsyncClient) -> None:
    account = await register(client)
    other = await register(client)
    ids = await seed_match(client, account)
    sent = await add_delivery(client, account, ids, runs_bat=4)

    # Re-sending the same delivery id under a new event id is a harmless no-op ...
    await applied(client, account, event("DELIVERY", {**sent, "runs_bat": 6}))
    snap = await snapshot(client, account, ids.match)
    assert len(snap["deliveries"]) == 1
    assert snap["deliveries"][0]["runs_bat"] == 4
    assert snap["innings"][0]["total_runs"] == 4
    # ... but never on somebody else's delivery.
    await rejected(client, other, event("DELIVERY", sent), "FORBIDDEN")


async def test_delivery_created_at_is_honoured(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    sent = await add_delivery(client, account, ids, created_at="2026-10-10T06:30:00+05:30")
    d = delivery_by_id(await snapshot(client, account, ids.match), sent["id"])
    assert d["created_at"].startswith("2026-10-10T01:00:00")


# ============================================================================ void


async def void(
    client: httpx.AsyncClient, account: Account, delivery_id: str, **extra: Any
) -> dict[str, Any]:
    return await one(
        client, account, event("DELIVERY", {"id": delivery_id, **extra}, action="VOID")
    )


async def test_void_last_delivery_updates_totals_and_never_reuses_sequences(
    client: httpx.AsyncClient,
) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    first = await add_delivery(client, account, ids, runs_bat=1)
    second = await add_delivery(client, account, ids, runs_bat=6)

    result = await void(client, account, second["id"], void_reason="scorer mistake")
    assert result["status"] == "APPLIED"
    snap = await snapshot(client, account, ids.match)
    voided = delivery_by_id(snap, second["id"])
    assert voided["is_voided"] is True
    assert voided["void_reason"] == "scorer mistake"
    assert voided["voided_at"] is not None
    assert snap["innings"][0]["total_runs"] == 1
    assert snap["innings"][0]["legal_balls"] == 1
    assert delivery_by_id(snap, first["id"])["is_voided"] is False

    # The replacement takes legal ball 2 again but gets a brand-new sequence number.
    third = await add_delivery(client, account, ids, runs_bat=2)
    snap = await snapshot(client, account, ids.match)
    replacement = delivery_by_id(snap, third["id"])
    assert (replacement["delivery_sequence"], replacement["legal_ball_number"]) == (3, 2)
    assert [d["delivery_sequence"] for d in snap["deliveries"]] == [1, 2, 3]  # voided one is kept
    assert snap["innings"][0]["total_runs"] == 3


async def test_only_the_last_active_delivery_can_be_voided(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    first = await add_delivery(client, account, ids)
    second = await add_delivery(client, account, ids)
    third = await add_delivery(client, account, ids)

    result = await void(client, account, first["id"])
    assert (result["status"], result["error"]["code"]) == ("REJECTED", "NOT_LAST_DELIVERY")

    assert (await void(client, account, third["id"]))["status"] == "APPLIED"
    # With the third voided, the second is now the last active delivery.
    assert (await void(client, account, first["id"]))["error"]["code"] == "NOT_LAST_DELIVERY"
    assert (await void(client, account, second["id"]))["status"] == "APPLIED"
    assert (await void(client, account, first["id"]))["status"] == "APPLIED"
    snap = await snapshot(client, account, ids.match)
    assert all(d["is_voided"] for d in snap["deliveries"])
    assert (snap["innings"][0]["total_runs"], snap["innings"][0]["legal_balls"]) == (0, 0)


async def test_voiding_twice_is_idempotent(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    await add_delivery(client, account, ids, runs_bat=1)
    second = await add_delivery(client, account, ids, runs_bat=4)
    assert (await void(client, account, second["id"], void_reason="first"))["status"] == "APPLIED"
    # A different event id for an already voided delivery: no error, nothing changes.
    assert (await void(client, account, second["id"], void_reason="second"))["status"] == "APPLIED"
    snap = await snapshot(client, account, ids.match)
    assert delivery_by_id(snap, second["id"])["void_reason"] == "first"
    assert snap["innings"][0]["total_runs"] == 1


async def test_voiding_a_wicket_restores_the_wicket_count(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    wicket = await add_delivery(
        client,
        account,
        ids,
        is_wicket=True,
        dismissal_type="CAUGHT",
        dismissed_player_id=ids.striker,
    )
    assert (await snapshot(client, account, ids.match))["innings"][0]["wickets"] == 1
    await void(client, account, wicket["id"])
    assert (await snapshot(client, account, ids.match))["innings"][0]["wickets"] == 0


async def test_void_of_unknown_or_foreign_delivery(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner)
    sent = await add_delivery(client, owner, ids)

    assert (await void(client, owner, uid()))["error"]["code"] == "ENTITY_NOT_FOUND"
    assert (await void(client, intruder, sent["id"]))["error"]["code"] == "FORBIDDEN"
    assert (await snapshot(client, owner, ids.match))["deliveries"][0]["is_voided"] is False


async def test_void_reason_is_limited_to_100_characters(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    sent = await add_delivery(client, account, ids)
    result = await void(client, account, sent["id"], void_reason="x" * 101)
    assert (result["status"], result["error"]["code"]) == ("REJECTED", "INVALID_PAYLOAD")


async def test_a_voided_delivery_frees_the_over_limit(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, overs=1)
    sent = [await add_delivery(client, account, ids) for _ in range(6)]
    await rejected(client, account, event("DELIVERY", delivery_payload(ids)), "OVER_LIMIT_EXCEEDED")
    await void(client, account, sent[-1]["id"])
    await add_delivery(client, account, ids, runs_bat=3)
    snap = await snapshot(client, account, ids.match)
    assert snap["innings"][0]["legal_balls"] == 6
    assert len(snap["deliveries"]) == 7


# ============================================================================ decisions


def decision_payload(delivery_id: str, **overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": uid(),
        "delivery_id": delivery_id,
        "decision_type": "WIDE",
        "automated_result": "WIDE",
        "confidence": 0.82,
        "decision_status": "REVIEW_RECOMMENDED",
        "decision_source": "AI_ASSIST",
        "evidence": {"lateral_offset": 1.4, "notes": ["near the line"]},
    }
    payload.update(overrides)
    return payload


async def test_decision_create_then_manual_override(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    delivery = await add_delivery(client, account, ids, is_wide=True, runs_extras=1)
    payload = decision_payload(delivery["id"], created_at="2026-10-10T08:15:00Z")
    await applied(client, account, event("DELIVERY_DECISION", payload))
    await applied(
        client,
        account,
        event(
            "DELIVERY_DECISION",
            {
                **payload,
                "final_result": "NOT_WIDE",
                "decision_status": "MANUAL_OVERRIDE",
                "decision_source": "MANUAL",
            },
        ),
    )
    [row] = (await snapshot(client, account, ids.match))["delivery_decisions"]
    assert row["id"] == payload["id"]
    assert row["decision_status"] == "MANUAL_OVERRIDE"
    assert row["decision_source"] == "MANUAL"
    assert row["final_result"] == "NOT_WIDE"
    assert row["automated_result"] == "WIDE"
    assert row["evidence"]["notes"] == ["near the line"]
    assert row["created_at"].startswith("2026-10-10T08:15:00")


async def test_decision_may_omit_optional_fields(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    delivery = await add_delivery(client, account, ids)
    minimal = {
        "id": uid(),
        "delivery_id": delivery["id"],
        "decision_type": "EDGE",
        "decision_status": "INCONCLUSIVE",
        "decision_source": "AI_ASSIST",
    }
    await applied(client, account, event("DELIVERY_DECISION", minimal))
    [row] = (await snapshot(client, account, ids.match))["delivery_decisions"]
    assert row["confidence"] is None
    assert row["evidence"] is None
    assert row["final_result"] is None


async def test_decision_cannot_move_to_another_delivery(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    first = await add_delivery(client, account, ids)
    second = await add_delivery(client, account, ids)
    payload = decision_payload(first["id"])
    await applied(client, account, event("DELIVERY_DECISION", payload))
    await rejected(
        client,
        account,
        event("DELIVERY_DECISION", {**payload, "delivery_id": second["id"]}),
        "INVALID_STATE",
    )


async def test_decision_delivery_must_exist_and_be_owned(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner)
    delivery = await add_delivery(client, owner, ids)
    await rejected(
        client, owner, event("DELIVERY_DECISION", decision_payload(uid())), "PARENT_NOT_FOUND"
    )
    await rejected(
        client, intruder, event("DELIVERY_DECISION", decision_payload(delivery["id"])), "FORBIDDEN"
    )


@pytest.mark.parametrize(
    "extra",
    [
        {"decision_type": "OFFSIDE"},
        {"decision_status": "MAYBE"},
        {"decision_source": "ROBOT"},
        {"confidence": 1.01},
        {"evidence": {"blob": "x" * 70_000}},
        {"evidence": "text"},
        {"automated_result": "x" * 41},
    ],
)
async def test_decision_payload_validation(
    client: httpx.AsyncClient, extra: dict[str, Any]
) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    delivery = await add_delivery(client, account, ids)
    await rejected(
        client,
        account,
        event("DELIVERY_DECISION", decision_payload(delivery["id"], **extra)),
        "INVALID_PAYLOAD",
    )


async def test_decision_stays_after_the_delivery_is_voided(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    delivery = await add_delivery(client, account, ids, is_wide=True, runs_extras=1)
    await applied(client, account, event("DELIVERY_DECISION", decision_payload(delivery["id"])))
    await void(client, account, delivery["id"])
    snap = await snapshot(client, account, ids.match)
    assert len(snap["delivery_decisions"]) == 1
    assert snap["deliveries"][0]["is_voided"] is True


# ============================================================================ trajectories


def trajectory_payload(delivery_id: str, points: int = 3, **overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": uid(),
        "delivery_id": delivery_id,
        "sampling_fps": 30,
        "points_compressed": [
            [i * 33.0, 0.1 + i * 0.001, 0.9 - i * 0.001, 0.8] for i in range(points)
        ],
        "model_version": "mock-ball-1",
    }
    payload.update(overrides)
    return payload


async def test_trajectory_create_and_replace(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    delivery = await add_delivery(client, account, ids)
    payload = trajectory_payload(delivery["id"], points=5)
    await applied(client, account, event("TRAJECTORY_SNAPSHOT", payload))
    await applied(
        client,
        account,
        event(
            "TRAJECTORY_SNAPSHOT",
            {**payload, "sampling_fps": 60, "points_compressed": [[0, 0.5, 0.5, 1]]},
        ),
    )
    [row] = (await snapshot(client, account, ids.match))["trajectory_snapshots"]
    assert row["sampling_fps"] == 60
    assert row["points_compressed"] == [[0, 0.5, 0.5, 1]]
    assert row["model_version"] == "mock-ball-1"


async def test_trajectory_accepts_up_to_600_points(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    delivery = await add_delivery(client, account, ids)
    await applied(
        client, account, event("TRAJECTORY_SNAPSHOT", trajectory_payload(delivery["id"], 600))
    )
    await rejected(
        client,
        account,
        event("TRAJECTORY_SNAPSHOT", trajectory_payload(delivery["id"], 601)),
        "INVALID_PAYLOAD",
    )


@pytest.mark.parametrize(
    "points",
    [
        [[0, 0.1, 0.1]],  # 3 numbers instead of 4
        [[0, 0.1, 0.1, 0.5, 9]],
        [[-1, 0.1, 0.1, 0.5]],  # negative timestamp
        [[0, 0.1, 0.1, 1.5]],  # confidence above 1
        [[0, 0.1, 0.1, -0.5]],
        [["0", 0.1, 0.1, 0.5]],
        "points",
    ],
)
async def test_trajectory_point_validation(client: httpx.AsyncClient, points: Any) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    delivery = await add_delivery(client, account, ids)
    await rejected(
        client,
        account,
        event("TRAJECTORY_SNAPSHOT", trajectory_payload(delivery["id"], points_compressed=points)),
        "INVALID_PAYLOAD",
    )


async def test_trajectory_references_and_ownership(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    intruder = await register(client)
    ids = await seed_match(client, owner)
    first = await add_delivery(client, owner, ids)
    second = await add_delivery(client, owner, ids)
    payload = trajectory_payload(first["id"])
    await rejected(
        client, owner, event("TRAJECTORY_SNAPSHOT", trajectory_payload(uid())), "PARENT_NOT_FOUND"
    )
    await rejected(client, intruder, event("TRAJECTORY_SNAPSHOT", payload), "FORBIDDEN")
    await applied(client, owner, event("TRAJECTORY_SNAPSHOT", payload))
    await rejected(
        client,
        owner,
        event("TRAJECTORY_SNAPSHOT", {**payload, "delivery_id": second["id"]}),
        "INVALID_STATE",
    )


# ============================================================================ remaining edge cases


async def test_wicket_detection_update_may_restate_detected_at(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    payload = wicket_detection_payload(ids.match)
    await applied(client, account, event("WICKET_DETECTION", payload))
    await applied(
        client,
        account,
        event("WICKET_DETECTION", {**payload, "detected_at": "2026-10-10T09:00:00Z"}),
    )
    [row] = (await snapshot(client, account, ids.match))["wicket_detections"]
    assert row["detected_at"].startswith("2026-10-10T09:00:00")


async def test_trajectory_update_may_restate_created_at(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    delivery = await add_delivery(client, account, ids)
    payload = trajectory_payload(delivery["id"])
    await applied(client, account, event("TRAJECTORY_SNAPSHOT", payload))
    await applied(
        client,
        account,
        event("TRAJECTORY_SNAPSHOT", {**payload, "created_at": "2026-10-10T09:30:00Z"}),
    )
    [row] = (await snapshot(client, account, ids.match))["trajectory_snapshots"]
    assert row["created_at"].startswith("2026-10-10T09:30:00")


async def test_an_innings_cannot_be_moved_to_another_match_with_the_same_teams(
    client: httpx.AsyncClient,
) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    second_match = uid()
    await applied(
        client,
        account,
        event(
            "MATCH",
            {
                "id": second_match,
                "team_a_id": ids.team_a,
                "team_b_id": ids.team_b,
                "status": "LIVE",
            },
        ),
    )
    moved = {
        "id": ids.innings,
        "match_id": second_match,
        "innings_number": 1,
        "batting_team_id": ids.team_a,
        "bowling_team_id": ids.team_b,
        "started_at": iso(),
    }
    await rejected(client, account, event("INNINGS", moved), "INVALID_STATE")
