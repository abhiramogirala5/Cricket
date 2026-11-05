from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import httpx
import jwt
import pytest
from fastapi import FastAPI
from sqlalchemy import select, update

from app.core.config import Settings
from app.core.security import create_access_token
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.services import auth_service
from tests.conftest import ClientFactory
from tests.helpers import API, PASSWORD, Account, register


async def _set_active(app: FastAPI, user_id: str, active: bool) -> None:
    async with app.state.session_factory() as session:
        await session.execute(
            update(User).where(User.id == uuid.UUID(user_id)).values(is_active=active)
        )
        await session.commit()


async def test_register_returns_user_and_tokens(client: httpx.AsyncClient) -> None:
    response = await client.post(
        f"{API}/auth/register",
        json={"email": "  Asha@Example.COM ", "password": PASSWORD, "display_name": "  Asha Rao  "},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["user"]["email"] == "asha@example.com"
    assert body["user"]["display_name"] == "Asha Rao"
    assert body["user"]["phone"] is None
    assert "password" not in str(body).lower().replace("password_", "")
    tokens = body["tokens"]
    assert tokens["token_type"] == "bearer"
    assert tokens["expires_in"] == 15 * 60
    assert len(tokens["refresh_token"]) >= 43  # >= 256 bits, url-safe base64
    assert uuid.UUID(body["user"]["id"])
    assert body["user"]["created_at"].endswith("Z")


async def test_register_duplicate_email_is_case_insensitive(client: httpx.AsyncClient) -> None:
    await register(client, "dup@example.com")
    response = await client.post(
        f"{API}/auth/register",
        json={"email": "DUP@example.com", "password": PASSWORD, "display_name": "Other"},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "EMAIL_ALREADY_REGISTERED"


@pytest.mark.parametrize(
    "payload",
    [
        {"email": "a@example.com", "password": "short", "display_name": "A"},
        {"email": "a@example.com", "password": "x" * 129, "display_name": "A"},
        {"email": "not-an-email", "password": PASSWORD, "display_name": "A"},
        {"email": "a@example.com", "password": PASSWORD, "display_name": "   "},
        {"email": "a@example.com", "password": PASSWORD, "display_name": "x" * 101},
        {"email": "a@example.com", "password": PASSWORD},
        {"email": "a@example.com", "password": PASSWORD, "display_name": "A", "is_active": False},
        {"email": "a" * 250 + "@example.com", "password": PASSWORD, "display_name": "A"},
    ],
)
async def test_register_validation_errors(
    client: httpx.AsyncClient, payload: dict[str, object]
) -> None:
    response = await client.post(f"{API}/auth/register", json=payload)
    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "VALIDATION_ERROR"
    assert error["request_id"]
    for detail in error["details"]:
        assert set(detail) == {"loc", "msg", "type"}  # never echoes the submitted value
    assert PASSWORD not in response.text


async def test_login_success_and_failures(client: httpx.AsyncClient) -> None:
    account = await register(client, "login@example.com")
    ok = await client.post(
        f"{API}/auth/login", json={"email": "LOGIN@example.com", "password": account.password}
    )
    assert ok.status_code == 200
    assert ok.json()["user"]["id"] == account.user_id

    wrong = await client.post(
        f"{API}/auth/login", json={"email": "login@example.com", "password": "wrong password"}
    )
    unknown = await client.post(
        f"{API}/auth/login", json={"email": "nobody@example.com", "password": "wrong password"}
    )
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json()["error"]["code"] == unknown.json()["error"]["code"] == "INVALID_CREDENTIALS"
    assert wrong.json()["error"]["message"] == unknown.json()["error"]["message"]


async def test_login_disabled_account(client: httpx.AsyncClient, app: FastAPI) -> None:
    account = await register(client, "off@example.com")
    await _set_active(app, account.user_id, False)
    response = await client.post(
        f"{API}/auth/login", json={"email": account.email, "password": account.password}
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "ACCOUNT_DISABLED"


async def test_refresh_rotates_tokens(client: httpx.AsyncClient) -> None:
    account = await register(client)
    first = await client.post(f"{API}/auth/refresh", json={"refresh_token": account.refresh_token})
    assert first.status_code == 200
    pair = first.json()
    assert pair["refresh_token"] != account.refresh_token
    assert pair["expires_in"] == 900

    reuse = await client.post(f"{API}/auth/refresh", json={"refresh_token": account.refresh_token})
    assert reuse.status_code == 401
    assert reuse.json()["error"]["code"] == "INVALID_REFRESH_TOKEN"

    # Within the grace window the family survives, so the new token still works.
    second = await client.post(f"{API}/auth/refresh", json={"refresh_token": pair["refresh_token"]})
    assert second.status_code == 200

    me = await client.get(
        f"{API}/users/me", headers={"Authorization": f"Bearer {pair['access_token']}"}
    )
    assert me.status_code == 200


async def test_refresh_reuse_after_grace_revokes_family(client_factory: ClientFactory) -> None:
    async with client_factory(refresh_reuse_grace_seconds=0) as c:
        account = await register(c)
        rotated = await c.post(f"{API}/auth/refresh", json={"refresh_token": account.refresh_token})
        newest = rotated.json()["refresh_token"]
        # Replaying the old token (after the zero-second grace window) means theft ...
        replay = await c.post(f"{API}/auth/refresh", json={"refresh_token": account.refresh_token})
        assert replay.status_code == 401
        # ... so the whole family is dead now, including the newest token.
        after = await c.post(f"{API}/auth/refresh", json={"refresh_token": newest})
        assert after.status_code == 401
        assert after.json()["error"]["code"] == "INVALID_REFRESH_TOKEN"


async def test_refresh_unknown_expired_and_disabled(
    client: httpx.AsyncClient, app: FastAPI
) -> None:
    unknown = await client.post(f"{API}/auth/refresh", json={"refresh_token": "nope"})
    assert unknown.status_code == 401
    assert unknown.json()["error"]["code"] == "INVALID_REFRESH_TOKEN"

    expired_account = await register(client)
    async with app.state.session_factory() as session:
        await session.execute(
            update(RefreshToken)
            .where(RefreshToken.user_id == uuid.UUID(expired_account.user_id))
            .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
        )
        await session.commit()
    expired = await client.post(
        f"{API}/auth/refresh", json={"refresh_token": expired_account.refresh_token}
    )
    assert expired.status_code == 401

    disabled_account = await register(client)
    await _set_active(app, disabled_account.user_id, False)
    disabled = await client.post(
        f"{API}/auth/refresh", json={"refresh_token": disabled_account.refresh_token}
    )
    assert disabled.status_code == 403
    assert disabled.json()["error"]["code"] == "ACCOUNT_DISABLED"


async def test_only_the_hash_of_a_refresh_token_is_stored(
    client: httpx.AsyncClient, app: FastAPI
) -> None:
    account = await register(client)
    async with app.state.session_factory() as session:
        stored = (await session.scalars(select(RefreshToken.token_hash))).all()
    assert len(stored) == 1
    assert stored[0] != account.refresh_token
    assert len(stored[0]) == 64


async def test_logout_revokes_and_is_idempotent(client: httpx.AsyncClient) -> None:
    account = await register(client)
    out = await client.post(f"{API}/auth/logout", json={"refresh_token": account.refresh_token})
    assert out.status_code == 204
    assert out.content == b""
    again = await client.post(f"{API}/auth/logout", json={"refresh_token": account.refresh_token})
    assert again.status_code == 204
    unknown = await client.post(f"{API}/auth/logout", json={"refresh_token": "unknown"})
    assert unknown.status_code == 204
    refresh = await client.post(
        f"{API}/auth/refresh", json={"refresh_token": account.refresh_token}
    )
    assert refresh.status_code == 401
    missing = await client.post(f"{API}/auth/logout", json={})
    assert missing.status_code == 422


async def test_protected_endpoint_token_errors(
    client: httpx.AsyncClient, settings: Settings
) -> None:
    none = await client.get(f"{API}/users/me")
    assert none.status_code == 401
    assert none.json()["error"]["code"] == "NOT_AUTHENTICATED"

    basic = await client.get(f"{API}/users/me", headers={"Authorization": "Basic abc"})
    assert basic.json()["error"]["code"] == "NOT_AUTHENTICATED"

    garbage = await client.get(f"{API}/users/me", headers={"Authorization": "Bearer garbage"})
    assert garbage.json()["error"]["code"] == "INVALID_TOKEN"

    account = await register(client)
    expired = create_access_token(
        settings, uuid.UUID(account.user_id), datetime.now(UTC) - timedelta(hours=1)
    )
    expired_response = await client.get(
        f"{API}/users/me", headers={"Authorization": f"Bearer {expired}"}
    )
    assert expired_response.status_code == 401
    assert expired_response.json()["error"]["code"] == "TOKEN_EXPIRED"

    now = int(datetime.now(UTC).timestamp())
    base = {"sub": account.user_id, "iat": now, "exp": now + 300, "jti": "x"}
    for claims, secret in (
        ({**base, "type": "refresh"}, settings.jwt_secret_key),
        ({**base, "type": "access"}, "a-completely-different-secret-of-sufficient-length"),
        ({**base, "type": "access", "sub": "not-a-uuid"}, settings.jwt_secret_key),
        ({**base, "type": "access", "sub": str(uuid.uuid4())}, settings.jwt_secret_key),
    ):
        token = jwt.encode(claims, secret, algorithm="HS256")
        response = await client.get(f"{API}/users/me", headers={"Authorization": f"Bearer {token}"})
        assert response.status_code == 401, claims
        assert response.json()["error"]["code"] == "INVALID_TOKEN", claims

    unsigned = jwt.encode({**base, "type": "access"}, key="", algorithm="none")
    response = await client.get(f"{API}/users/me", headers={"Authorization": f"Bearer {unsigned}"})
    assert response.json()["error"]["code"] == "INVALID_TOKEN"


async def test_valid_token_of_disabled_user_is_rejected(
    client: httpx.AsyncClient, app: FastAPI
) -> None:
    account = await register(client)
    await _set_active(app, account.user_id, False)
    response = await client.get(f"{API}/users/me", headers=account.headers)
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "ACCOUNT_DISABLED"


async def test_auth_endpoints_are_rate_limited(client_factory: ClientFactory) -> None:
    async with client_factory(rate_limit_auth_requests=3, rate_limit_auth_window_seconds=60) as c:
        body = {"email": "x@example.com", "password": "whatever-password"}
        statuses = [(await c.post(f"{API}/auth/login", json=body)).status_code for _ in range(3)]
        assert statuses == [401, 401, 401]
        limited = await c.post(f"{API}/auth/login", json=body)
        assert limited.status_code == 429
        assert limited.json()["error"]["code"] == "RATE_LIMITED"
        assert int(limited.headers["retry-after"]) >= 1
        # Other endpoints are not limited.
        assert (await c.get("/health")).status_code == 200


async def test_account_is_available_after_registration(client: httpx.AsyncClient) -> None:
    account: Account = await register(client, display_name="Meera")
    me = await client.get(f"{API}/users/me", headers=account.headers)
    assert me.status_code == 200
    assert me.json()["display_name"] == "Meera"


async def test_concurrent_registration_of_the_same_email_is_a_conflict(
    client: httpx.AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Two requests pass the "email is free" check together; the unique index decides."""
    first = await register(client)

    async def pretend_free(*_args: object, **_kwargs: object) -> None:
        return None

    monkeypatch.setattr(auth_service, "get_user_by_email", pretend_free)
    response = await client.post(
        f"{API}/auth/register",
        json={"email": first.email, "password": PASSWORD, "display_name": "Second"},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "EMAIL_ALREADY_REGISTERED"


async def test_login_upgrades_a_password_hash_made_with_weaker_parameters(
    client: httpx.AsyncClient, client_factory: ClientFactory, app: FastAPI
) -> None:
    account = await register(client)  # hashed with the cheap test parameters (time cost 1)
    async with app.state.session_factory() as session:
        before = await session.scalar(select(User.password_hash).where(User.email == account.email))

    async with client_factory(argon2_time_cost=2, argon2_memory_cost_kib=16) as stricter:
        response = await stricter.post(
            f"{API}/auth/login", json={"email": account.email, "password": PASSWORD}
        )
        assert response.status_code == 200

    async with app.state.session_factory() as session:
        after = await session.scalar(select(User.password_hash).where(User.email == account.email))
    assert after != before
    assert "t=2" in str(after)
    # The new hash still verifies, and so does a login through the original configuration.
    again = await client.post(
        f"{API}/auth/login", json={"email": account.email, "password": PASSWORD}
    )
    assert again.status_code == 200
