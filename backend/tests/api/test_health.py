from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any

import httpx
from fastapi import FastAPI

from app.db.session import get_session


async def test_health_is_ok(client: httpx.AsyncClient) -> None:
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert response.headers["x-request-id"]


async def test_ready_checks_database(client: httpx.AsyncClient) -> None:
    response = await client.get("/health/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready", "database": "ok"}


async def test_ready_reports_503_when_the_database_is_down(app: FastAPI) -> None:
    class BrokenSession:
        async def execute(self, *_args: Any, **_kwargs: Any) -> None:
            raise OSError("connection refused: secret-host:5432")

    async def broken_session() -> AsyncIterator[BrokenSession]:
        yield BrokenSession()

    app.dependency_overrides[get_session] = broken_session
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health/ready")
        liveness = await client.get("/health")

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    assert "secret-host" not in response.text  # infrastructure details never leak
    assert liveness.status_code == 200  # liveness does not depend on the database
