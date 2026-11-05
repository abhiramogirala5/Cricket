"""Small builders used by many tests."""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

import httpx

API = "/api/v1"
PASSWORD = "correct horse battery"


def uid() -> str:
    return str(uuid.uuid4())


def iso(moment: datetime | None = None) -> str:
    return (moment or datetime.now(UTC)).strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass
class Account:
    user_id: str
    email: str
    password: str
    access_token: str
    refresh_token: str
    headers: dict[str, str] = field(default_factory=dict)


async def register(
    client: httpx.AsyncClient,
    email: str | None = None,
    password: str = PASSWORD,
    display_name: str = "Asha Rao",
) -> Account:
    address = email or f"user-{uuid.uuid4().hex[:10]}@example.com"
    response = await client.post(
        f"{API}/auth/register",
        json={"email": address, "password": password, "display_name": display_name},
    )
    assert response.status_code == 201, response.text
    body = response.json()
    access = body["tokens"]["access_token"]
    return Account(
        user_id=body["user"]["id"],
        email=body["user"]["email"],
        password=password,
        access_token=access,
        refresh_token=body["tokens"]["refresh_token"],
        headers={"Authorization": f"Bearer {access}"},
    )


def event(
    entity_type: str,
    payload: dict[str, Any],
    *,
    action: str = "UPSERT",
    event_id: str | None = None,
) -> dict[str, Any]:
    return {
        "event_id": event_id or uid(),
        "entity_type": entity_type,
        "action": action,
        "payload": payload,
        "client_created_at": iso(),
    }


async def push(
    client: httpx.AsyncClient, account: Account, events: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    response = await client.post(
        f"{API}/sync/push", json={"events": events}, headers=account.headers
    )
    assert response.status_code == 200, response.text
    results: list[dict[str, Any]] = response.json()["results"]
    assert [r["event_id"] for r in results] == [e["event_id"] for e in events]
    return results


async def push_ok(
    client: httpx.AsyncClient, account: Account, events: list[dict[str, Any]]
) -> None:
    results = await push(client, account, events)
    for result in results:
        assert result["status"] == "APPLIED", result


@dataclass
class MatchIds:
    team_a: str
    team_b: str
    match: str
    innings: str
    bowler: str
    striker: str
    non_striker: str
    extra_batter: str
    other_bowler: str


def player_payload(player_id: str, name: str, **extra: Any) -> dict[str, Any]:
    return {"id": player_id, "display_name": name, **extra}


async def seed_match(
    client: httpx.AsyncClient,
    account: Account,
    *,
    overs: int = 2,
    status: str = "LIVE",
    with_innings: bool = True,
) -> MatchIds:
    """Two teams, five players in a match, an innings (team A batting)."""
    ids = MatchIds(
        team_a=uid(),
        team_b=uid(),
        match=uid(),
        innings=uid(),
        bowler=uid(),
        striker=uid(),
        non_striker=uid(),
        extra_batter=uid(),
        other_bowler=uid(),
    )
    events = [
        event("TEAM", {"id": ids.team_a, "name": "Reds"}),
        event("TEAM", {"id": ids.team_b, "name": "Blues"}),
        event("PLAYER", player_payload(ids.striker, "Striker")),
        event("PLAYER", player_payload(ids.non_striker, "Non Striker")),
        event("PLAYER", player_payload(ids.extra_batter, "Extra Batter")),
        event("PLAYER", player_payload(ids.bowler, "Bowler")),
        event("PLAYER", player_payload(ids.other_bowler, "Other Bowler")),
        event(
            "MATCH",
            {
                "id": ids.match,
                "team_a_id": ids.team_a,
                "team_b_id": ids.team_b,
                "status": status,
                "overs_per_innings": overs,
                "match_name": "Sunday finals",
            },
        ),
    ]
    for player, team in (
        (ids.striker, ids.team_a),
        (ids.non_striker, ids.team_a),
        (ids.extra_batter, ids.team_a),
        (ids.bowler, ids.team_b),
        (ids.other_bowler, ids.team_b),
    ):
        events.append(
            event("MATCH_PLAYER", {"match_id": ids.match, "player_id": player, "team_id": team})
        )
    if with_innings:
        events.append(
            event(
                "INNINGS",
                {
                    "id": ids.innings,
                    "match_id": ids.match,
                    "innings_number": 1,
                    "batting_team_id": ids.team_a,
                    "bowling_team_id": ids.team_b,
                    "started_at": iso(),
                },
            )
        )
    await push_ok(client, account, events)
    return ids


def delivery_payload(ids: MatchIds, **overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": uid(),
        "innings_id": ids.innings,
        "bowler_id": ids.bowler,
        "striker_id": ids.striker,
        "non_striker_id": ids.non_striker,
        "runs_bat": 0,
        "runs_extras": 0,
    }
    payload.update(overrides)
    return payload
