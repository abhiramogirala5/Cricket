"""Portable column types and helpers in app.db.base."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta, timezone

import pytest
from sqlalchemy.dialects import sqlite

from app.db.base import UTCDateTime, in_check
from app.models.enums import BattingHand

DIALECT = sqlite.dialect()
IST = timezone(timedelta(hours=5, minutes=30))


def test_utc_datetime_stores_aware_values_in_utc() -> None:
    value = datetime(2026, 10, 10, 13, 0, tzinfo=IST)
    stored = UTCDateTime().process_bind_param(value, DIALECT)
    assert stored == datetime(2026, 10, 10, 7, 30, tzinfo=UTC)
    assert stored is not None
    assert stored.utcoffset() == timedelta(0)


def test_utc_datetime_treats_naive_values_as_utc() -> None:
    naive = datetime(2026, 10, 10, 7, 30)
    assert UTCDateTime().process_bind_param(naive, DIALECT) == datetime(
        2026, 10, 10, 7, 30, tzinfo=UTC
    )


def test_utc_datetime_always_returns_aware_utc() -> None:
    column = UTCDateTime()
    from_sqlite = column.process_result_value(datetime(2026, 10, 10, 7, 30), DIALECT)
    from_postgres = column.process_result_value(datetime(2026, 10, 10, 13, 0, tzinfo=IST), DIALECT)
    assert from_sqlite == from_postgres == datetime(2026, 10, 10, 7, 30, tzinfo=UTC)
    assert from_postgres is not None
    assert from_postgres.tzinfo is not None


def test_utc_datetime_passes_none_through() -> None:
    column = UTCDateTime()
    assert column.process_bind_param(None, DIALECT) is None
    assert column.process_result_value(None, DIALECT) is None


def test_in_check_from_enum_and_list() -> None:
    assert in_check("batting_hand", BattingHand) == "batting_hand IN ('LEFT','RIGHT','UNKNOWN')"
    assert in_check("x", ["A", "B"]) == "x IN ('A','B')"


@pytest.mark.parametrize("values", [[], ["ONLY"]])
def test_in_check_edge_cases(values: list[str]) -> None:
    assert in_check("c", values) == f"c IN ({','.join(repr(v) for v in values)})"
