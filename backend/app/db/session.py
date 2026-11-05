"""Async engine and session factory."""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any

from fastapi import Request
from sqlalchemy import event
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool

from app.core.config import Settings


def configure_sqlite(engine: AsyncEngine) -> None:
    """Make SQLite behave like a real database for our purposes.

    * foreign keys are enforced (``PRAGMA foreign_keys=ON``) so cascades match PostgreSQL;
    * SAVEPOINT / ``begin_nested()`` work (the pysqlite driver needs manual transaction control).
    """

    @event.listens_for(engine.sync_engine, "connect")
    def _on_connect(dbapi_connection: Any, _record: Any) -> None:
        dbapi_connection.isolation_level = None
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    @event.listens_for(engine.sync_engine, "begin")
    def _on_begin(connection: Any) -> None:
        connection.exec_driver_sql("BEGIN")


def create_engine(settings: Settings) -> AsyncEngine:
    kwargs: dict[str, Any] = {
        "echo": settings.db_echo,
        # Never put bound parameters (emails, hashes, tokens) into exception messages / logs.
        "hide_parameters": True,
    }
    if settings.is_sqlite:
        if ":memory:" in settings.database_url or settings.database_url.endswith("sqlite://"):
            kwargs["poolclass"] = StaticPool
            kwargs["connect_args"] = {"check_same_thread": False}
    else:
        kwargs.update(
            pool_size=settings.db_pool_size,
            max_overflow=settings.db_max_overflow,
            pool_timeout=settings.db_pool_timeout_seconds,
            pool_pre_ping=True,
        )
    engine = create_async_engine(settings.database_url, **kwargs)
    if settings.is_sqlite:
        configure_sqlite(engine)
    return engine


def create_session_factory(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine, expire_on_commit=False, autoflush=True)


async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    """FastAPI dependency: one session per request. Services commit explicitly."""
    factory: async_sessionmaker[AsyncSession] = request.app.state.session_factory
    async with factory() as session:
        yield session
