"""Envelope, idempotency, isolation and ownership rules of POST /sync/push (API_CONTRACT §5.1-5.2)."""

from __future__ import annotations

from typing import Any

import httpx
import pytest
from fastapi import FastAPI
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.models.enums import EntityType, SyncAction
from app.models.player import Player
from app.models.sync_event import SyncEvent
from app.services.sync import handlers_roster, registry
from app.services.sync import service as sync_service
from app.services.sync.errors import SyncRejection
from tests.helpers import (
    API,
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


async def _status(client: httpx.AsyncClient, account: Any, ev: dict[str, Any]) -> dict[str, Any]:
    [result] = await push(client, account, [ev])
    return result


async def test_requires_authentication(client: httpx.AsyncClient) -> None:
    response = await client.post(
        f"{API}/sync/push", json={"events": [event("TEAM", {"id": uid(), "name": "A"})]}
    )
    assert response.status_code == 401


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"events": []},
        {"events": "nope"},
        {"events": [{"event_id": "x"}]},
        {"events": [event("TEAM", {"id": uid(), "name": "A"})], "extra": 1},
    ],
)
async def test_request_level_validation(client: httpx.AsyncClient, body: dict[str, Any]) -> None:
    account = await register(client)
    response = await client.post(f"{API}/sync/push", json=body, headers=account.headers)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


async def test_batch_limit_is_100_events(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ok = [event("TEAM", {"id": uid(), "name": f"T{i}"}) for i in range(100)]
    assert len(await push(client, account, ok)) == 100
    too_many = [event("TEAM", {"id": uid(), "name": f"T{i}"}) for i in range(101)]
    response = await client.post(
        f"{API}/sync/push", json={"events": too_many}, headers=account.headers
    )
    assert response.status_code == 422


async def test_results_have_applied_status_and_server_time(client: httpx.AsyncClient) -> None:
    account = await register(client)
    response = await client.post(
        f"{API}/sync/push",
        json={"events": [event("TEAM", {"id": uid(), "name": "Reds"})]},
        headers=account.headers,
    )
    body = response.json()
    assert body["results"][0]["status"] == "APPLIED"
    assert body["results"][0]["error"] is None
    assert body["server_time"].endswith("Z")


async def test_resending_an_applied_event_is_a_duplicate(
    client: httpx.AsyncClient, app: FastAPI
) -> None:
    account = await register(client)
    ev = event("PLAYER", player_payload(uid(), "Asha"))
    assert (await _status(client, account, ev))["status"] == "APPLIED"
    again = dict(ev, payload=player_payload(ev["payload"]["id"], "Changed Name"))
    assert (await _status(client, account, again))["status"] == "DUPLICATE"
    players = (await client.get(f"{API}/players", headers=account.headers)).json()["items"]
    assert [p["display_name"] for p in players] == ["Asha"]  # the duplicate changed nothing
    async with app.state.session_factory() as session:
        assert await session.scalar(select(func.count()).select_from(SyncEvent)) == 1


async def test_duplicate_inside_one_batch(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ev = event("TEAM", {"id": uid(), "name": "Reds"})
    results = await push(client, account, [ev, ev])
    assert [r["status"] for r in results] == ["APPLIED", "DUPLICATE"]


async def test_event_ids_are_scoped_per_user(client: httpx.AsyncClient) -> None:
    first, second = await register(client), await register(client)
    shared_event_id = uid()
    a = event("TEAM", {"id": uid(), "name": "A"}, event_id=shared_event_id)
    b = event("TEAM", {"id": uid(), "name": "B"}, event_id=shared_event_id)
    assert (await _status(client, first, a))["status"] == "APPLIED"
    assert (await _status(client, second, b))["status"] == "APPLIED"


async def test_rejected_events_are_not_recorded_and_can_be_retried(
    client: httpx.AsyncClient,
) -> None:
    account = await register(client)
    team_a, team_b, match_id = uid(), uid(), uid()
    match_event = event("MATCH", {"id": match_id, "team_a_id": team_a, "team_b_id": team_b})
    first = await _status(client, account, match_event)
    assert first["status"] == "REJECTED"
    assert first["error"]["code"] == "PARENT_NOT_FOUND"

    await push_ok(
        client,
        account,
        [event("TEAM", {"id": team_a, "name": "A"}), event("TEAM", {"id": team_b, "name": "B"})],
    )
    retry = await _status(client, account, match_event)  # the very same event_id
    assert retry["status"] == "APPLIED"


async def test_one_bad_event_does_not_affect_the_others(
    client: httpx.AsyncClient, app: FastAPI
) -> None:
    account = await register(client)
    good_team, good_player = uid(), uid()
    results = await push(
        client,
        account,
        [
            event("TEAM", {"id": good_team, "name": "Reds"}),
            event("PLAYER", {"id": uid(), "display_name": ""}),  # invalid payload
            event("PLAYER", player_payload(good_player, "Asha")),
        ],
    )
    assert [r["status"] for r in results] == ["APPLIED", "REJECTED", "APPLIED"]
    assert results[1]["error"]["code"] == "INVALID_PAYLOAD"
    assert (await client.get(f"{API}/teams", headers=account.headers)).json()["total"] == 1
    assert (await client.get(f"{API}/players", headers=account.headers)).json()["total"] == 1
    async with app.state.session_factory() as session:
        assert await session.scalar(select(func.count()).select_from(SyncEvent)) == 2


async def test_events_are_applied_in_array_order(client: httpx.AsyncClient) -> None:
    account = await register(client)
    team_a, team_b = uid(), uid()
    results = await push(
        client,
        account,
        [
            event("MATCH", {"id": uid(), "team_a_id": team_a, "team_b_id": team_b}),
            event("TEAM", {"id": team_a, "name": "A"}),
            event("TEAM", {"id": team_b, "name": "B"}),
        ],
    )
    assert [r["status"] for r in results] == ["REJECTED", "APPLIED", "APPLIED"]
    assert results[0]["error"]["code"] == "PARENT_NOT_FOUND"


@pytest.mark.parametrize(
    ("entity", "action"),
    [
        ("UNKNOWN_THING", "UPSERT"),
        ("PLAYER", "DELETE"),
        ("PLAYER", "VOID"),
        ("MATCH", "VOID"),
        ("DELIVERY", "DELETE"),
        ("TEAM", "EXPLODE"),
        ("player", "UPSERT"),
    ],
)
async def test_unsupported_events(client: httpx.AsyncClient, entity: str, action: str) -> None:
    account = await register(client)
    ev = event("TEAM", {"id": uid(), "name": "A"})
    ev["entity_type"], ev["action"] = entity, action
    result = await _status(client, account, ev)
    assert result["status"] == "REJECTED"
    assert result["error"]["code"] == "UNSUPPORTED_EVENT"


@pytest.mark.parametrize(
    "payload",
    [
        {"id": "not-a-uuid", "name": "A"},
        {"id": "00000000-0000-4000-8000-000000000001"},  # missing name
        {
            "id": "00000000-0000-4000-8000-000000000001",
            "name": "A",
            "owner_id": "x",
        },  # unknown field
        {"id": "00000000-0000-4000-8000-000000000001", "name": 5},
        {"id": "00000000-0000-4000-8000-000000000001", "name": "x" * 101},
        {"id": "00000000-0000-4000-8000-000000000001", "name": "   "},
        {},
    ],
)
async def test_invalid_payloads(client: httpx.AsyncClient, payload: dict[str, Any]) -> None:
    account = await register(client)
    result = await _status(client, account, event("TEAM", payload))
    assert result["status"] == "REJECTED"
    assert result["error"]["code"] == "INVALID_PAYLOAD"
    assert result["error"]["message"]


async def test_payload_types_are_strict(client: httpx.AsyncClient) -> None:
    account = await register(client)
    ids = await seed_match(client, account)
    for override in ({"runs_bat": "1"}, {"runs_bat": 1.5}, {"is_wide": 1}, {"is_wide": "true"}):
        result = await _status(
            client, account, event("DELIVERY", delivery_payload(ids, **override))
        )
        assert result["error"]["code"] == "INVALID_PAYLOAD", override
    naive = await _status(
        client, account, event("DELIVERY", delivery_payload(ids, created_at="2026-10-08T07:33:00"))
    )
    assert naive["error"]["code"] == "INVALID_PAYLOAD"
    bad_enum = await _status(
        client, account, event("PLAYER", player_payload(uid(), "A", batting_hand="BOTH"))
    )
    assert bad_enum["error"]["code"] == "INVALID_PAYLOAD"


async def test_unexpected_exception_becomes_internal_error_and_is_retryable(
    client: httpx.AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    account = await register(client)
    team_id = uid()
    ev = event("TEAM", {"id": team_id, "name": "Reds"})
    original = handlers_roster.upsert_team

    async def broken(*_args: Any, **_kwargs: Any) -> None:
        raise RuntimeError("boom")

    route = registry.ROUTES[(EntityType.TEAM, SyncAction.UPSERT)]
    monkeypatch.setitem(
        registry.ROUTES, (EntityType.TEAM, SyncAction.UPSERT), registry.Route(route.schema, broken)
    )
    results = await push(client, account, [ev, event("PLAYER", player_payload(uid(), "Asha"))])
    assert results[0]["status"] == "REJECTED"
    assert results[0]["error"]["code"] == "INTERNAL_ERROR"
    assert "boom" not in results[0]["error"]["message"]
    assert results[1]["status"] == "APPLIED"

    monkeypatch.setitem(registry.ROUTES, (EntityType.TEAM, SyncAction.UPSERT), route)
    assert original is route.handler
    assert (await _status(client, account, ev))["status"] == "APPLIED"


# ------------------------------------------------------------------ ownership


async def test_cannot_overwrite_another_users_entities(client: httpx.AsyncClient) -> None:
    owner, intruder = await register(client), await register(client)
    ids = await seed_match(client, owner)
    attempts = [
        event("PLAYER", player_payload(ids.striker, "Hijacked")),
        event("TEAM", {"id": ids.team_a, "name": "Hijacked"}),
        event(
            "MATCH",
            {
                "id": ids.match,
                "team_a_id": ids.team_a,
                "team_b_id": ids.team_b,
                "status": "COMPLETED",
            },
        ),
    ]
    for ev in attempts:
        result = await _status(client, intruder, ev)
        assert result["status"] == "REJECTED", ev["entity_type"]
        assert result["error"]["code"] == "FORBIDDEN", ev["entity_type"]

    players = (await client.get(f"{API}/players", headers=owner.headers)).json()["items"]
    assert "Hijacked" not in {p["display_name"] for p in players}


async def test_cannot_attach_children_to_another_users_match(client: httpx.AsyncClient) -> None:
    owner, intruder = await register(client), await register(client)
    ids = await seed_match(client, owner)
    own_player = uid()
    await push_ok(client, intruder, [event("PLAYER", player_payload(own_player, "Mine"))])

    forbidden = [
        event(
            "MATCH_PLAYER", {"match_id": ids.match, "player_id": own_player, "team_id": ids.team_a}
        ),
        event("MATCH_RULES", {"match_id": ids.match}),
        event(
            "INNINGS",
            {
                "id": uid(),
                "match_id": ids.match,
                "innings_number": 2,
                "batting_team_id": ids.team_b,
                "bowling_team_id": ids.team_a,
                "started_at": iso(),
            },
        ),
        event("DELIVERY", delivery_payload(ids)),
        event("DELIVERY", {"id": uid()}, action="VOID"),
        event("MATCH", {"id": ids.match}, action="DELETE"),
    ]
    results = await push(client, intruder, forbidden)
    assert [r["error"]["code"] for r in results[:4]] == ["FORBIDDEN"] * 4
    assert results[4]["error"]["code"] == "ENTITY_NOT_FOUND"
    assert results[5]["error"]["code"] == "FORBIDDEN"

    snapshot = await client.get(f"{API}/matches/{ids.match}/snapshot", headers=owner.headers)
    assert snapshot.json()["deliveries"] == []


async def test_cannot_reference_another_users_player_or_team(client: httpx.AsyncClient) -> None:
    owner, intruder = await register(client), await register(client)
    ids = await seed_match(client, owner)
    own_team_a, own_team_b, own_match = uid(), uid(), uid()
    await push_ok(
        client,
        intruder,
        [
            event("TEAM", {"id": own_team_a, "name": "Mine A"}),
            event("TEAM", {"id": own_team_b, "name": "Mine B"}),
            event("MATCH", {"id": own_match, "team_a_id": own_team_a, "team_b_id": own_team_b}),
        ],
    )
    stolen_team = await _status(
        client,
        intruder,
        event("MATCH", {"id": uid(), "team_a_id": ids.team_a, "team_b_id": own_team_b}),
    )
    assert stolen_team["error"]["code"] == "FORBIDDEN"
    stolen_player = await _status(
        client,
        intruder,
        event(
            "MATCH_PLAYER", {"match_id": own_match, "player_id": ids.striker, "team_id": own_team_a}
        ),
    )
    assert stolen_player["error"]["code"] == "FORBIDDEN"


async def test_sync_ledger_cascades_with_the_user(client: httpx.AsyncClient, app: FastAPI) -> None:
    account = await register(client)
    await push_ok(client, account, [event("PLAYER", player_payload(uid(), "Asha"))])
    async with app.state.session_factory() as session:
        assert await session.scalar(select(func.count()).select_from(Player)) == 1


# ------------------------------------------------------------------ concurrency & odd inputs


def _raise_integrity_error(*_args: Any, **_kwargs: Any) -> None:
    raise IntegrityError("INSERT ...", {}, Exception("duplicate key"))


async def test_integrity_error_with_the_event_in_the_ledger_means_duplicate(
    client: httpx.AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Another request applied this event between our ledger check and our insert."""
    account = await register(client)
    answers = iter([False, True])

    async def ledger_check(*_args: Any, **_kwargs: Any) -> bool:
        return next(answers)

    async def losing_handler(*_args: Any, **_kwargs: Any) -> None:
        _raise_integrity_error()

    route = registry.ROUTES[(EntityType.TEAM, SyncAction.UPSERT)]
    monkeypatch.setitem(
        registry.ROUTES,
        (EntityType.TEAM, SyncAction.UPSERT),
        registry.Route(route.schema, losing_handler),
    )
    monkeypatch.setattr(sync_service, "_already_applied", ledger_check)
    result = await _status(client, account, event("TEAM", {"id": uid(), "name": "Reds"}))
    assert result["status"] == "DUPLICATE"


async def test_integrity_error_without_a_ledger_entry_is_an_internal_error(
    client: httpx.AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    account = await register(client)

    async def failing_handler(*_args: Any, **_kwargs: Any) -> None:
        _raise_integrity_error()

    route = registry.ROUTES[(EntityType.TEAM, SyncAction.UPSERT)]
    monkeypatch.setitem(
        registry.ROUTES,
        (EntityType.TEAM, SyncAction.UPSERT),
        registry.Route(route.schema, failing_handler),
    )
    ok = event("PLAYER", player_payload(uid(), "Asha"))
    results = await push(client, account, [event("TEAM", {"id": uid(), "name": "Reds"}), ok])
    assert results[0]["status"] == "REJECTED"
    assert results[0]["error"]["code"] == "INTERNAL_ERROR"
    assert "duplicate key" not in results[0]["error"]["message"]
    assert results[1]["status"] == "APPLIED"


def test_a_payload_that_cannot_be_serialised_is_an_invalid_payload() -> None:
    route = registry.ROUTES[(EntityType.TEAM, SyncAction.UPSERT)]
    with pytest.raises(SyncRejection) as excinfo:
        sync_service._parse_payload(route, {"id": object()})
    assert excinfo.value.code == "INVALID_PAYLOAD"
    assert "not valid JSON" in excinfo.value.message
