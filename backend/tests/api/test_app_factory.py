"""create_app wiring: engine ownership, Sentry and state."""

from __future__ import annotations

from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncEngine

from app import __version__, main
from app.main import create_app
from app.services.storage import StorageError, SupabaseStorage
from tests.conftest import make_settings
from tests.fakes import FakeStorage


async def test_app_owning_its_engine_disposes_it_on_shutdown(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    disposed: list[AsyncEngine] = []
    real_dispose = AsyncEngine.dispose

    async def recording_dispose(self: AsyncEngine, close: bool = True) -> None:
        disposed.append(self)
        await real_dispose(self, close)

    monkeypatch.setattr(AsyncEngine, "dispose", recording_dispose)
    app = create_app(make_settings())
    async with app.router.lifespan_context(app):
        assert disposed == []
    assert disposed == [app.state.engine]


async def test_app_does_not_dispose_an_engine_it_was_given(engine: Any) -> None:
    app = create_app(make_settings(), engine=engine)
    async with app.router.lifespan_context(app):
        pass
    # The caller still owns the engine, so it must keep working.
    async with engine.connect() as connection:
        assert (await connection.exec_driver_sql("SELECT 1")).scalar_one() == 1


def test_state_carries_the_shared_components() -> None:
    settings = make_settings()
    app = create_app(settings)
    assert app.state.settings is settings
    assert app.state.session_factory is not None
    assert app.state.password_service is not None
    assert app.state.auth_rate_limiter is not None
    assert app.version == __version__


def test_sentry_is_initialised_only_when_a_dsn_is_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[dict[str, Any]] = []
    monkeypatch.setattr(main.sentry_sdk, "init", lambda **kwargs: calls.append(kwargs))

    create_app(make_settings(sentry_dsn=None))
    assert calls == []

    create_app(
        make_settings(
            sentry_dsn="https://key@o1.ingest.sentry.io/1", sentry_traces_sample_rate=0.25
        )
    )
    [call] = calls
    assert call["dsn"] == "https://key@o1.ingest.sentry.io/1"
    assert call["environment"] == "test"
    assert call["release"] == __version__
    assert call["traces_sample_rate"] == 0.25
    assert call["send_default_pii"] is False


async def test_app_creates_the_replay_bucket_at_start_and_closes_the_storage_at_stop(
    monkeypatch: pytest.MonkeyPatch, engine: Any
) -> None:
    fake = FakeStorage()
    monkeypatch.setattr(main, "_make_storage", lambda settings: fake)
    app = create_app(make_settings(), engine=engine)
    assert app.state.storage is fake
    async with app.router.lifespan_context(app):
        assert fake.bucket_checks == 1
        assert fake.closed is False
    assert fake.closed is True


async def test_a_storage_outage_at_start_does_not_stop_the_api(
    monkeypatch: pytest.MonkeyPatch, engine: Any
) -> None:
    fake = FakeStorage()
    fake.fail_with = StorageError("down")
    monkeypatch.setattr(main, "_make_storage", lambda settings: fake)
    app = create_app(make_settings(), engine=engine)
    async with app.router.lifespan_context(app):
        assert fake.bucket_checks == 1


def test_storage_is_built_only_when_supabase_is_configured() -> None:
    assert main._make_storage(make_settings()) is None
    configured = main._make_storage(
        make_settings(supabase_url="https://abc.supabase.co", supabase_service_role_key="k")
    )
    assert isinstance(configured, SupabaseStorage)
