from __future__ import annotations

import httpx
from fastapi import FastAPI
from sqlalchemy import func, select

from app.models.player import Player
from app.models.refresh_token import RefreshToken
from app.models.user import User
from tests.helpers import API, PASSWORD, event, push_ok, register, seed_match


async def test_patch_me_updates_fields(client: httpx.AsyncClient) -> None:
    account = await register(client)
    response = await client.patch(
        f"{API}/users/me",
        json={"display_name": "  New Name ", "phone": "+91 98765-43210"},
        headers=account.headers,
    )
    assert response.status_code == 200
    assert response.json()["display_name"] == "New Name"
    assert response.json()["phone"] == "+91 98765-43210"

    only_phone = await client.patch(
        f"{API}/users/me", json={"phone": None}, headers=account.headers
    )
    assert only_phone.status_code == 200
    assert only_phone.json()["phone"] is None
    assert only_phone.json()["display_name"] == "New Name"


async def test_patch_me_validation(client: httpx.AsyncClient) -> None:
    account = await register(client)
    for body in (
        {},
        {"phone": "abc"},
        {"phone": "1234"},
        {"phone": "1" * 26},
        {"display_name": ""},
        {"display_name": None},
        {"email": "other@example.com"},
    ):
        response = await client.patch(f"{API}/users/me", json=body, headers=account.headers)
        assert response.status_code == 422, body
        assert response.json()["error"]["code"] == "VALIDATION_ERROR"


async def test_delete_me_requires_correct_password(client: httpx.AsyncClient) -> None:
    account = await register(client)
    wrong = await client.request(
        "DELETE", f"{API}/users/me", json={"password": "not my password"}, headers=account.headers
    )
    assert wrong.status_code == 403
    assert wrong.json()["error"]["code"] == "PASSWORD_INCORRECT"
    still_there = await client.get(f"{API}/users/me", headers=account.headers)
    assert still_there.status_code == 200

    missing_body = await client.request("DELETE", f"{API}/users/me", headers=account.headers)
    assert missing_body.status_code == 422


async def test_delete_me_removes_user_and_all_data(client: httpx.AsyncClient, app: FastAPI) -> None:
    account = await register(client)
    other = await register(client)
    ids = await seed_match(client, account)
    await seed_match(client, other)
    await push_ok(
        client,
        account,
        [
            event(
                "DELIVERY",
                {
                    "id": "00000000-0000-4000-8000-000000000001",
                    "innings_id": ids.innings,
                    "bowler_id": ids.bowler,
                    "striker_id": ids.striker,
                    "non_striker_id": ids.non_striker,
                    "runs_bat": 4,
                    "runs_extras": 0,
                },
            )
        ],
    )

    response = await client.request(
        "DELETE", f"{API}/users/me", json={"password": PASSWORD}, headers=account.headers
    )
    assert response.status_code == 204

    after = await client.get(f"{API}/users/me", headers=account.headers)
    assert after.status_code == 401
    login = await client.post(
        f"{API}/auth/login", json={"email": account.email, "password": PASSWORD}
    )
    assert login.status_code == 401

    async with app.state.session_factory() as session:
        users = await session.scalar(select(func.count()).select_from(User))
        players = await session.scalar(select(func.count()).select_from(Player))
        tokens = await session.scalar(select(func.count()).select_from(RefreshToken))
    assert users == 1  # only the other account remains
    assert players == 5  # the other account's roster is untouched
    assert tokens == 1

    # The other account's data is still fully readable.
    still = await client.get(f"{API}/matches", headers=other.headers)
    assert still.json()["total"] == 1
