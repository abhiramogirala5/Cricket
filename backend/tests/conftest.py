"""Shared fixtures.

The suite runs on in-memory SQLite by default. Set ``TEST_DATABASE_URL`` to a PostgreSQL URL
(``postgresql+asyncpg://user:pass@host:port/db``) to run the very same tests against PostgreSQL;
the schema is dropped and re-created for every test in that mode, so use a throw-away database.
"""

from __future__ import annotations

import os
from collections.abc import AsyncIterator, Callable
from contextlib import AbstractAsyncContextManager, asynccontextmanager
from typing import Any

import httpx
import pytest
from fastapi import FastAPI
from sqlalchemy.ext.asyncio import AsyncEngine

import app.models
from app.core.config import Settings
from app.db.base import Base
from app.db.session import create_engine
from app.main import create_app
from tests.fakes import FakeStorage

TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")


def make_settings(**overrides: Any) -> Settings:
    values: dict[str, Any] = {
        "app_env": "test",
        "database_url": TEST_DATABASE_URL or "sqlite+aiosqlite://",
        "jwt_secret_key": "test-secret-key-" + "x" * 40,
        # Cheap Argon2 so the suite is fast; production defaults are in Settings.
        "argon2_time_cost": 1,
        "argon2_memory_cost_kib": 8,
        "argon2_parallelism": 1,
        "rate_limit_auth_requests": 1000,
        "log_level": "WARNING",
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


@pytest.fixture
def settings() -> Settings:
    return make_settings()


@pytest.fixture
async def engine(settings: Settings) -> AsyncIterator[AsyncEngine]:
    eng = create_engine(settings)
    async with eng.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield eng
    if TEST_DATABASE_URL:
        async with eng.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
    await eng.dispose()


@pytest.fixture
async def app(settings: Settings, engine: AsyncEngine) -> FastAPI:
    return create_app(settings, engine=engine)


@pytest.fixture
def storage() -> FakeStorage:
    return FakeStorage()


@pytest.fixture
async def replay_client(
    settings: Settings, engine: AsyncEngine, storage: FakeStorage
) -> AsyncIterator[httpx.AsyncClient]:
    """A client of an app whose replay storage is the in-memory ``storage``."""
    application = create_app(settings, engine=engine, storage=storage)
    transport = httpx.ASGITransport(app=application)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as http_client:
        yield http_client


@pytest.fixture
async def client(app: FastAPI) -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as http_client:
        yield http_client


ClientFactory = Callable[..., AbstractAsyncContextManager[httpx.AsyncClient]]


@pytest.fixture
def client_factory(engine: AsyncEngine) -> ClientFactory:
    """``async with client_factory(rate_limit_auth_requests=3) as c`` -> a client on custom settings."""

    @asynccontextmanager
    async def build(**overrides: Any) -> AsyncIterator[httpx.AsyncClient]:
        application = create_app(make_settings(**overrides), engine=engine)
        transport = httpx.ASGITransport(app=application)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as http_client:
            yield http_client

    return build
