"""Read endpoints (API_CONTRACT §4): pagination, ordering, filters, isolation and the snapshot."""

from __future__ import annotations

from typing import Any

import httpx
import pytest

from tests.helpers import (
    API,
    Account,
    delivery_payload,
    event,
    player_payload,
    push_ok,
    register,
    seed_match,
    uid,
)


async def get(
    client: httpx.AsyncClient, account: Account, path: str, **params: Any
) -> httpx.Response:
    return await client.get(f"{API}{path}", params=params or None, headers=account.headers)


# ---------------------------------------------------------------------------- authentication


@pytest.mark.parametrize("path", ["/players", "/teams", "/matches", f"/matches/{uid()}/snapshot"])
async def test_read_endpoints_require_authentication(client: httpx.AsyncClient, path: str) -> None:
    response = await client.get(f"{API}{path}")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "NOT_AUTHENTICATED"
    assert response.headers["www-authenticate"] == "Bearer"


# ---------------------------------------------------------------------------- players & teams


async def test_players_are_paginated_and_sorted_by_name(client: httpx.AsyncClient) -> None:
    account = await register(client)
    names = ["Zoya", "asha", "Bala", "Chitra", "Dev"]
    await push_ok(client, account, [event("PLAYER", player_payload(uid(), n)) for n in names])

    first = (await get(client, account, "/players", limit=2)).json()
    assert (first["total"], first["limit"], first["offset"]) == (5, 2, 0)
    second = (await get(client, account, "/players", limit=2, offset=2)).json()
    last = (await get(client, account, "/players", limit=2, offset=4)).json()
    beyond = (await get(client, account, "/players", limit=2, offset=10)).json()

    seen = [p["display_name"] for page in (first, second, last) for p in page["items"]]
    assert sorted(seen) == sorted(names)
    assert [len(p["items"]) for p in (first, second, last)] == [2, 2, 1]
    assert beyond["items"] == []
    assert beyond["total"] == 5
    # The order is stable: the same query twice returns the same page.
    assert (await get(client, account, "/players", limit=2, offset=2)).json() == second


async def test_player_shape(client: httpx.AsyncClient) -> None:
    account = await register(client)
    pid = uid()
    await push_ok(
        client,
        account,
        [event("PLAYER", player_payload(pid, "Asha", batting_hand="LEFT", declared_height_cm=165))],
    )
    [item] = (await get(client, account, "/players")).json()["items"]
    assert set(item) == {
        "id",
        "display_name",
        "batting_hand",
        "declared_height_cm",
        "created_at",
        "updated_at",
    }
    assert item["id"] == pid
    assert item["created_at"].endswith("Z")


async def test_teams_are_paginated_and_sorted_by_name(client: httpx.AsyncClient) -> None:
    account = await register(client)
    await push_ok(
        client,
        account,
        [event("TEAM", {"id": uid(), "name": n}) for n in ("Blues", "Alphas", "Cubs")],
    )
    page = (await get(client, account, "/teams", limit=2)).json()
    assert [t["name"] for t in page["items"]] == ["Alphas", "Blues"]
    assert page["total"] == 3
    rest = (await get(client, account, "/teams", limit=2, offset=2)).json()
    assert [t["name"] for t in rest["items"]] == ["Cubs"]


@pytest.mark.parametrize("path", ["/players", "/teams", "/matches"])
@pytest.mark.parametrize(
    "params",
    [{"limit": 0}, {"limit": 101}, {"limit": "many"}, {"offset": -1}, {"offset": "x"}],
)
async def test_pagination_parameters_are_validated(
    client: httpx.AsyncClient, path: str, params: dict[str, Any]
) -> None:
    account = await register(client)
    response = await get(client, account, path, **params)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


async def test_page_size_defaults_and_maximum(client: httpx.AsyncClient) -> None:
    account = await register(client)
    page = (await get(client, account, "/players")).json()
    assert (page["limit"], page["offset"]) == (50, 0)
    assert (await get(client, account, "/players", limit=100)).status_code == 200


async def test_lists_only_show_the_callers_own_data(client: httpx.AsyncClient) -> None:
    alice = await register(client)
    bob = await register(client)
    await seed_match(client, alice)
    await seed_match(client, bob)
    for path, expected in (("/players", 5), ("/teams", 2), ("/matches", 1)):
        for account in (alice, bob):
            assert (await get(client, account, path)).json()["total"] == expected


# ---------------------------------------------------------------------------- matches


async def test_matches_newest_first_with_status_filter(client: httpx.AsyncClient) -> None:
    account = await register(client)
    first = await seed_match(client, account, status="DRAFT", with_innings=False)
    second = await seed_match(client, account, status="LIVE")
    third = await seed_match(client, account, status="LIVE")

    everything = (await get(client, account, "/matches")).json()
    assert everything["total"] == 3
    assert [m["id"] for m in everything["items"]] == [third.match, second.match, first.match]

    live = (await get(client, account, "/matches", status="LIVE")).json()
    assert live["total"] == 2
    assert [m["id"] for m in live["items"]] == [third.match, second.match]

    drafts = (await get(client, account, "/matches", status="DRAFT")).json()
    assert [m["id"] for m in drafts["items"]] == [first.match]
    assert (await get(client, account, "/matches", status="COMPLETED")).json()["items"] == []

    paged = (await get(client, account, "/matches", limit=1, offset=1)).json()
    assert [m["id"] for m in paged["items"]] == [second.match]
    assert paged["total"] == 3


async def test_matches_status_filter_rejects_unknown_values(client: httpx.AsyncClient) -> None:
    account = await register(client)
    response = await get(client, account, "/matches", status="PAUSED")
    assert response.status_code == 422


async def test_match_summary_embeds_teams_and_live_innings_totals(
    client: httpx.AsyncClient,
) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    await push_ok(
        client,
        account,
        [
            event("DELIVERY", delivery_payload(ids, runs_bat=4)),
            event("DELIVERY", delivery_payload(ids, runs_bat=1)),
            event(
                "DELIVERY",
                delivery_payload(
                    ids, is_wicket=True, dismissal_type="BOWLED", dismissed_player_id=ids.striker
                ),
            ),
        ],
    )
    [summary] = (await get(client, account, "/matches")).json()["items"]
    assert summary["id"] == ids.match
    assert summary["match_name"] == "Sunday finals"
    assert summary["status"] == "LIVE"
    assert summary["overs_per_innings"] == 2
    assert summary["team_a"] == {"id": ids.team_a, "name": "Reds"}
    assert summary["team_b"] == {"id": ids.team_b, "name": "Blues"}
    [innings] = summary["innings"]
    assert innings["batting_team_id"] == ids.team_a
    assert (innings["total_runs"], innings["wickets"], innings["legal_balls"]) == (5, 1, 3)
    assert innings["ended_at"] is None


async def test_match_without_innings_has_an_empty_innings_list(client: httpx.AsyncClient) -> None:
    account = await register(client)
    await seed_match(client, account, with_innings=False)
    [summary] = (await get(client, account, "/matches")).json()["items"]
    assert summary["innings"] == []


# ---------------------------------------------------------------------------- snapshot


async def test_snapshot_of_a_brand_new_match(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    body = (await get(client, account, f"/matches/{ids.match}/snapshot")).json()
    assert set(body) == {
        "match",
        "rules",
        "teams",
        "players",
        "match_players",
        "toss",
        "innings",
        "deliveries",
        "delivery_decisions",
        "scene_scans",
        "wicket_detections",
        "trajectory_snapshots",
    }
    assert body["match"]["id"] == ids.match
    assert body["match"]["owner_id"] == account.user_id
    assert body["rules"] is None
    assert body["toss"] is None
    assert body["innings"] == body["deliveries"] == body["delivery_decisions"] == []
    assert body["scene_scans"] == body["wicket_detections"] == body["trajectory_snapshots"] == []
    assert sorted(t["name"] for t in body["teams"]) == ["Blues", "Reds"]
    assert len(body["players"]) == len(body["match_players"]) == 5


async def test_snapshot_is_complete_and_includes_voided_deliveries(
    client: httpx.AsyncClient,
) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    d1, d2 = delivery_payload(ids, runs_bat=2), delivery_payload(ids, runs_bat=6)
    scan = {
        "id": uid(),
        "match_id": ids.match,
        "scan_duration_ms": 1000,
        "overall_confidence": 0.9,
        "model_version": "mock-scene-1",
    }
    detection = {
        "id": uid(),
        "match_id": ids.match,
        "scene_scan_id": scan["id"],
        "wicket_family": "CHAIR",
        "bounding_box": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.4},
        "target_polygon": [{"x": 0.1, "y": 0.1}, {"x": 0.3, "y": 0.1}, {"x": 0.3, "y": 0.5}],
        "object_confidence": 0.9,
        "temporal_stability": 0.9,
        "context_confidence": 0.9,
        "final_confidence": 0.9,
        "model_version": "mock-wicket-1",
    }
    await push_ok(
        client,
        account,
        [
            event("MATCH_RULES", {"match_id": ids.match, "edge_review_enabled": False}),
            event(
                "TOSS",
                {"id": uid(), "match_id": ids.match, "call_choice": "HEADS", "result": "HEADS"},
            ),
            event("SCENE_SCAN", scan),
            event("WICKET_DETECTION", detection),
            event("DELIVERY", d1),
            event("DELIVERY", d2),
            event(
                "DELIVERY_DECISION",
                {
                    "id": uid(),
                    "delivery_id": d1["id"],
                    "decision_type": "EDGE",
                    "decision_status": "AUTO_CALL",
                    "decision_source": "AI_ASSIST",
                },
            ),
            event(
                "TRAJECTORY_SNAPSHOT",
                {
                    "id": uid(),
                    "delivery_id": d2["id"],
                    "sampling_fps": 30,
                    "points_compressed": [[0, 0.1, 0.2, 0.9]],
                    "model_version": "mock-ball-1",
                },
            ),
            event("DELIVERY", {"id": d2["id"], "void_reason": "typo"}, action="VOID"),
        ],
    )
    body = (await get(client, account, f"/matches/{ids.match}/snapshot")).json()

    assert body["rules"]["edge_review_enabled"] is False
    assert body["toss"]["result"] == "HEADS"
    assert [d["id"] for d in body["deliveries"]] == [d1["id"], d2["id"]]
    assert [d["is_voided"] for d in body["deliveries"]] == [False, True]
    assert body["deliveries"][1]["void_reason"] == "typo"
    assert len(body["delivery_decisions"]) == 1
    assert len(body["trajectory_snapshots"]) == 1
    assert body["wicket_detections"][0]["scene_scan_id"] == scan["id"]
    assert body["scene_scans"][0]["id"] == scan["id"]
    [innings] = body["innings"]
    assert (innings["total_runs"], innings["legal_balls"]) == (
        2,
        1,
    )  # the voided six is not counted


async def test_snapshot_lists_only_players_of_that_match(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account, with_innings=False)
    bystander = uid()
    await push_ok(client, account, [event("PLAYER", player_payload(bystander, "Bystander"))])
    body = (await get(client, account, f"/matches/{ids.match}/snapshot")).json()
    assert bystander not in {p["id"] for p in body["players"]}
    assert {mp["player_id"] for mp in body["match_players"]} == {p["id"] for p in body["players"]}


async def test_snapshot_keeps_innings_and_deliveries_in_order(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    sent = [delivery_payload(ids, runs_bat=i % 5) for i in range(8)]
    await push_ok(client, account, [event("DELIVERY", d) for d in sent])
    body = (await get(client, account, f"/matches/{ids.match}/snapshot")).json()
    assert [d["id"] for d in body["deliveries"]] == [d["id"] for d in sent]
    assert [d["delivery_sequence"] for d in body["deliveries"]] == list(range(1, 9))


async def test_snapshot_of_unknown_or_foreign_match_is_404(client: httpx.AsyncClient) -> None:
    owner = await register(client)
    other = await register(client)
    ids = await seed_match(client, owner)

    unknown = await get(client, owner, f"/matches/{uid()}/snapshot")
    foreign = await get(client, other, f"/matches/{ids.match}/snapshot")
    for response in (unknown, foreign):
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "NOT_FOUND"
    # A foreign match must be indistinguishable from a missing one.
    assert unknown.json()["error"]["message"] == foreign.json()["error"]["message"]


async def test_snapshot_rejects_a_malformed_match_id(client: httpx.AsyncClient) -> None:
    account = await register(client)
    response = await get(client, account, "/matches/not-a-uuid/snapshot")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"
