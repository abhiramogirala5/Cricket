"""Error envelope, request ids, body-size limit, CORS and production hardening."""

from __future__ import annotations

import json
from collections.abc import AsyncIterator

import httpx
import pytest
from fastapi import FastAPI
from sqlalchemy.ext.asyncio import AsyncEngine

from app.main import create_app
from tests.conftest import make_settings
from tests.helpers import API, event, register, uid


def assert_envelope(response: httpx.Response, status: int, code: str) -> dict[str, object]:
    assert response.status_code == status, response.text
    assert response.headers["content-type"].startswith("application/json")
    body = response.json()
    assert set(body) == {"error"}
    error = body["error"]
    assert error["code"] == code
    assert isinstance(error["message"], str)
    assert error["message"]
    assert error["request_id"] == response.headers["x-request-id"]
    return dict(error)


# ---------------------------------------------------------------------------- envelope


async def test_unknown_route_is_a_404_envelope(client: httpx.AsyncClient) -> None:
    error = assert_envelope(await client.get("/nope"), 404, "NOT_FOUND")
    assert error["message"] == "Resource not found."


async def test_wrong_method_is_a_405_envelope(client: httpx.AsyncClient) -> None:
    response = await client.delete("/health")
    assert_envelope(response, 405, "METHOD_NOT_ALLOWED")
    assert "GET" in response.headers["allow"]


async def test_invalid_json_body_is_a_422_envelope_without_echoing_the_input(
    client: httpx.AsyncClient,
) -> None:
    secret = "hunter2-do-not-leak"
    response = await client.post(
        f"{API}/auth/login",
        content=('{"email": "a@b.co", "password": "' + secret + '"').encode(),  # truncated JSON
        headers={"content-type": "application/json"},
    )
    error = assert_envelope(response, 422, "VALIDATION_ERROR")
    assert secret not in response.text
    for item in error["details"]:  # type: ignore[attr-defined]
        assert set(item) == {"loc", "msg", "type"}


async def test_validation_details_never_contain_submitted_values(client: httpx.AsyncClient) -> None:
    secret = "pw-9zq"  # too short on purpose
    response = await client.post(
        f"{API}/auth/register",
        json={"email": "not-an-email", "password": secret, "display_name": ""},
    )
    error = assert_envelope(response, 422, "VALIDATION_ERROR")
    details = error["details"]
    assert isinstance(details, list)
    assert len(details) >= 2
    locations = {tuple(item["loc"]) for item in details}
    assert ("body", "email") in locations
    assert ("body", "password") in locations
    assert secret not in json.dumps(error)


async def test_missing_token_has_a_www_authenticate_header(client: httpx.AsyncClient) -> None:
    response = await client.get(f"{API}/players")
    assert_envelope(response, 401, "NOT_AUTHENTICATED")
    assert response.headers["www-authenticate"] == "Bearer"


async def test_garbage_token_is_invalid_token(client: httpx.AsyncClient) -> None:
    response = await client.get(f"{API}/players", headers={"Authorization": "Bearer not.a.jwt"})
    assert_envelope(response, 401, "INVALID_TOKEN")


async def test_non_bearer_scheme_is_not_authenticated(client: httpx.AsyncClient) -> None:
    response = await client.get(f"{API}/players", headers={"Authorization": "Basic YTpi"})
    assert_envelope(response, 401, "NOT_AUTHENTICATED")


# ---------------------------------------------------------------------------- request id


async def test_a_request_id_is_generated_when_none_is_sent(client: httpx.AsyncClient) -> None:
    first = await client.get("/health")
    second = await client.get("/health")
    assert first.headers["x-request-id"] != second.headers["x-request-id"]
    assert len(first.headers["x-request-id"]) == 32


async def test_a_valid_request_id_is_echoed_everywhere(client: httpx.AsyncClient) -> None:
    rid = "client-req.123_abc"
    ok = await client.get("/health", headers={"X-Request-ID": rid})
    missing = await client.get("/nope", headers={"X-Request-ID": rid})
    assert ok.headers["x-request-id"] == rid
    error = assert_envelope(missing, 404, "NOT_FOUND")
    assert error["request_id"] == rid


@pytest.mark.parametrize(
    "bad",
    ["has space", "semi;colon", "x" * 65, "new\tline", "<script>"],
)
async def test_an_unsafe_request_id_is_replaced(client: httpx.AsyncClient, bad: str) -> None:
    response = await client.get("/health", headers={"X-Request-ID": bad})
    returned = response.headers["x-request-id"]
    assert returned != bad
    assert len(returned) == 32


# ---------------------------------------------------------------------------- body size


@pytest.fixture
async def small_body_client(engine: AsyncEngine) -> AsyncIterator[httpx.AsyncClient]:
    app = create_app(make_settings(max_request_body_bytes=1024), engine=engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def test_oversized_body_is_rejected_by_content_length(
    small_body_client: httpx.AsyncClient,
) -> None:
    response = await small_body_client.post(
        f"{API}/auth/login", json={"email": "a@b.co", "password": "x" * 5000}
    )
    assert_envelope(response, 413, "PAYLOAD_TOO_LARGE")


async def test_oversized_streamed_body_is_rejected_without_content_length(
    small_body_client: httpx.AsyncClient,
) -> None:
    async def chunks() -> AsyncIterator[bytes]:
        for _ in range(10):
            yield b" " * 400  # 4000 bytes in total, no Content-Length header

    request = small_body_client.build_request(
        "POST", f"{API}/auth/login", content=chunks(), headers={"content-type": "application/json"}
    )
    assert "content-length" not in request.headers
    response = await small_body_client.send(request)
    assert_envelope(response, 413, "PAYLOAD_TOO_LARGE")


async def test_body_within_the_limit_is_processed(small_body_client: httpx.AsyncClient) -> None:
    response = await small_body_client.post(
        f"{API}/auth/login", json={"email": "nobody@example.com", "password": "whatever-it-is"}
    )
    assert_envelope(response, 401, "INVALID_CREDENTIALS")


async def test_sync_batches_fit_within_the_default_limit(client: httpx.AsyncClient) -> None:
    account = await register(client)
    events = [event("TEAM", {"id": uid(), "name": "T" * 100}) for _ in range(100)]
    response = await client.post(
        f"{API}/sync/push", json={"events": events}, headers=account.headers
    )
    assert response.status_code == 200


# ---------------------------------------------------------------------------- unhandled errors


async def test_unhandled_exception_becomes_a_500_envelope_without_details(app: FastAPI) -> None:
    @app.get("/boom")
    async def boom() -> None:
        raise RuntimeError("secret internal detail")

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/boom", headers={"X-Request-ID": "trace-me"})
    error = assert_envelope(response, 500, "INTERNAL_ERROR")
    assert error["request_id"] == "trace-me"
    assert "secret internal detail" not in response.text


# ---------------------------------------------------------------------------- CORS


@pytest.fixture
async def cors_client(engine: AsyncEngine) -> AsyncIterator[httpx.AsyncClient]:
    settings = make_settings(
        cors_allowed_origins="https://app.example.com, https://admin.example.com"
    )
    assert settings.cors_allowed_origins == ["https://app.example.com", "https://admin.example.com"]
    app = create_app(settings, engine=engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def test_preflight_from_an_allowed_origin(cors_client: httpx.AsyncClient) -> None:
    response = await cors_client.options(
        f"{API}/sync/push",
        headers={
            "Origin": "https://app.example.com",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "https://app.example.com"
    assert "POST" in response.headers["access-control-allow-methods"]
    assert "x-request-id" in response.headers


async def test_preflight_from_an_unknown_origin_is_refused(cors_client: httpx.AsyncClient) -> None:
    response = await cors_client.options(
        f"{API}/sync/push",
        headers={"Origin": "https://evil.example.org", "Access-Control-Request-Method": "POST"},
    )
    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers


async def test_actual_response_exposes_the_request_id_to_allowed_origins(
    cors_client: httpx.AsyncClient,
) -> None:
    response = await cors_client.get("/health", headers={"Origin": "https://admin.example.com"})
    assert response.headers["access-control-allow-origin"] == "https://admin.example.com"
    assert "x-request-id" in response.headers["access-control-expose-headers"].lower()


async def test_no_cors_headers_are_sent_when_no_origins_are_configured(
    client: httpx.AsyncClient,
) -> None:
    response = await client.get("/health", headers={"Origin": "https://app.example.com"})
    assert "access-control-allow-origin" not in response.headers


# ---------------------------------------------------------------------------- docs exposure


async def test_openapi_docs_are_available_outside_production(client: httpx.AsyncClient) -> None:
    assert (await client.get("/docs")).status_code == 200
    schema = (await client.get("/openapi.json")).json()
    assert "/api/v1/sync/push" in schema["paths"]


async def test_openapi_docs_are_disabled_in_production(engine: AsyncEngine) -> None:
    settings = make_settings(
        app_env="production",
        database_url="postgresql+asyncpg://user:pass@localhost:5432/db",
        jwt_secret_key="p" * 48,
    )
    app = create_app(settings, engine=engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        for path in ("/docs", "/redoc", "/openapi.json"):
            assert_envelope(await client.get(path), 404, "NOT_FOUND")
        assert (await client.get("/health")).status_code == 200
