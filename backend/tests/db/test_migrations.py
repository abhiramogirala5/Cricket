"""Alembic: upgrade/downgrade round trip and drift between the migration and ``app.models``.

Runs on SQLite by default and on PostgreSQL when ``TEST_DATABASE_URL`` is set.
"""

from __future__ import annotations

import asyncio
import io
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

import pytest
import sqlalchemy as sa
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

import app.models  # noqa: F401  (registers the tables)
from app.db.base import Base
from tests.conftest import TEST_DATABASE_URL

BACKEND_DIR = Path(__file__).resolve().parents[2]
MODEL_TABLES = set(Base.metadata.tables)


def alembic_config(url: str) -> Config:
    config = Config(str(BACKEND_DIR / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", url.replace("%", "%%"))
    return config


async def run(func: Any, config: Config, *args: Any, **kwargs: Any) -> None:
    """Alembic's async env uses ``asyncio.run``, so it has to run outside the test's event loop."""
    await asyncio.to_thread(func, config, *args, **kwargs)


@pytest.fixture
async def url(tmp_path: Path) -> AsyncIterator[str]:
    value = TEST_DATABASE_URL or f"sqlite+aiosqlite:///{tmp_path / 'migrate.db'}"
    await _wipe(value)
    yield value
    await _wipe(value)


async def _wipe(url: str) -> None:
    engine = create_async_engine(url)
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.execute(sa.text("DROP TABLE IF EXISTS alembic_version"))
    finally:
        await engine.dispose()


@pytest.fixture
async def engine(url: str) -> AsyncIterator[AsyncEngine]:
    eng = create_async_engine(url)
    yield eng
    await eng.dispose()


async def table_names(engine: AsyncEngine) -> set[str]:
    async with engine.connect() as conn:
        names = await conn.run_sync(lambda c: set(sa.inspect(c).get_table_names()))
    return names - {"alembic_version"}


# ---------------------------------------------------------------------------- history


def test_history_is_a_single_line_from_the_initial_schema() -> None:
    script = ScriptDirectory.from_config(alembic_config("sqlite+aiosqlite://"))
    assert script.get_heads() == ["0002"]
    assert script.get_base() == "0001"
    assert [rev.revision for rev in script.walk_revisions()] == ["0002", "0001"]


# ---------------------------------------------------------------------------- upgrade / downgrade


async def test_upgrade_creates_every_model_table(url: str, engine: AsyncEngine) -> None:
    assert await table_names(engine) == set()
    await run(command.upgrade, alembic_config(url), "head")
    assert await table_names(engine) == MODEL_TABLES


async def test_downgrade_removes_everything_and_upgrade_can_be_repeated(
    url: str, engine: AsyncEngine
) -> None:
    config = alembic_config(url)
    await run(command.upgrade, config, "head")
    await run(command.upgrade, config, "head")  # already at head: a no-op
    await run(command.downgrade, config, "base")
    assert await table_names(engine) == set()
    await run(command.upgrade, config, "head")
    assert await table_names(engine) == MODEL_TABLES


async def test_version_table_records_the_head(url: str, engine: AsyncEngine) -> None:
    await run(command.upgrade, alembic_config(url), "head")
    async with engine.connect() as conn:
        version = (
            await conn.execute(sa.text("SELECT version_num FROM alembic_version"))
        ).scalar_one()
    assert version == "0002"


async def test_offline_sql_generation_works_without_a_database() -> None:
    config = alembic_config("postgresql+asyncpg://user:pass@localhost:5432/never_contacted")
    buffer = io.StringIO()
    config.output_buffer = buffer
    await run(command.upgrade, config, "head", sql=True)
    sql = buffer.getvalue()
    assert "CREATE TABLE users" in sql
    assert "CREATE TABLE trajectory_snapshots" in sql
    assert "CREATE TABLE replay_clips" in sql
    assert "JSONB" in sql
    # Supabase publishes public tables through its Data API; row-level security closes it.
    assert 'ALTER TABLE "users" ENABLE ROW LEVEL SECURITY' in sql
    assert 'ALTER TABLE "replay_clips" ENABLE ROW LEVEL SECURITY' in sql
    assert "INSERT INTO alembic_version" in sql


# ---------------------------------------------------------------------------- drift


async def test_migrated_schema_matches_the_models(url: str, engine: AsyncEngine) -> None:
    await run(command.upgrade, alembic_config(url), "head")

    def diff(connection: sa.Connection) -> list[Any]:
        context = MigrationContext.configure(connection, opts={"compare_type": True})
        return list(compare_metadata(context, Base.metadata))

    async with engine.connect() as conn:
        differences = await conn.run_sync(diff)
    assert differences == []


async def test_constraint_and_index_names_match_the_models(url: str, engine: AsyncEngine) -> None:
    """``compare_metadata`` ignores CHECK constraints, so compare names (and the FK rules) here."""
    await run(command.upgrade, alembic_config(url), "head")

    def collect(connection: sa.Connection) -> dict[str, dict[str, set[str]]]:
        inspector = sa.inspect(connection)
        found: dict[str, dict[str, set[str]]] = {}
        for table in MODEL_TABLES:
            found[table] = {
                "check": {c["name"] for c in inspector.get_check_constraints(table) if c["name"]},
                "unique": {c["name"] for c in inspector.get_unique_constraints(table) if c["name"]},
                "fk": {c["name"] for c in inspector.get_foreign_keys(table) if c["name"]},
                "index": {i["name"] for i in inspector.get_indexes(table) if i["name"]},
                "pk": {inspector.get_pk_constraint(table).get("name") or ""} - {""},
            }
        return found

    async with engine.connect() as conn:
        actual = await conn.run_sync(collect)

    for name, table in Base.metadata.tables.items():
        expected_checks = {
            c.name for c in table.constraints if isinstance(c, sa.CheckConstraint) and c.name
        }
        expected_fks = {c.name for c in table.constraints if isinstance(c, sa.ForeignKeyConstraint)}
        expected_unique = {c.name for c in table.constraints if isinstance(c, sa.UniqueConstraint)}
        assert actual[name]["check"] == expected_checks, name
        assert actual[name]["fk"] == expected_fks, name
        assert actual[name]["index"] >= {i.name for i in table.indexes}, name
        # SQLite reports unique constraints but not their names for composite keys in older versions.
        if engine.dialect.name == "postgresql":
            assert actual[name]["unique"] == expected_unique, name
            assert actual[name]["pk"] == {table.primary_key.name}, name


async def test_cascade_rules_survive_the_migration(url: str, engine: AsyncEngine) -> None:
    await run(command.upgrade, alembic_config(url), "head")

    def rules(connection: sa.Connection) -> dict[tuple[str, str], str | None]:
        inspector = sa.inspect(connection)
        out: dict[tuple[str, str], str | None] = {}
        for table in MODEL_TABLES:
            for fk in inspector.get_foreign_keys(table):
                out[(table, fk["constrained_columns"][0])] = fk["options"].get("ondelete")
        return out

    async with engine.connect() as conn:
        actual = await conn.run_sync(rules)

    expected: dict[tuple[str, str], str | None] = {}
    for table in Base.metadata.tables.values():
        for fk_constraint in (
            c for c in table.constraints if isinstance(c, sa.ForeignKeyConstraint)
        ):
            column = fk_constraint.column_keys[0]
            expected[(table.name, column)] = fk_constraint.ondelete
    assert actual == expected
    assert actual[("matches", "owner_id")] == "CASCADE"
    assert actual[("deliveries", "innings_id")] == "CASCADE"
    assert actual[("deliveries", "wicket_detection_id")] == "SET NULL"
    assert actual[("deliveries", "bowler_id")] is None
