"""JSON log lines: shape, request id, extras and no double access logging."""

from __future__ import annotations

import io
import json
import logging
from collections.abc import Iterator

import pytest

from app.core.logging import JsonFormatter, configure_logging, request_id_ctx


@pytest.fixture
def captured() -> Iterator[io.StringIO]:
    """Route the root logger into a buffer with the production formatter, restore afterwards."""
    root = logging.getLogger()
    saved_handlers, saved_level = root.handlers[:], root.level
    buffer = io.StringIO()
    handler = logging.StreamHandler(buffer)
    handler.setFormatter(JsonFormatter())
    root.handlers[:] = [handler]
    root.setLevel(logging.DEBUG)
    yield buffer
    root.handlers[:] = saved_handlers
    root.setLevel(saved_level)


def last_line(buffer: io.StringIO) -> dict[str, object]:
    lines = [line for line in buffer.getvalue().splitlines() if line.strip()]
    parsed: dict[str, object] = json.loads(lines[-1])
    return parsed


def test_a_line_is_one_json_object_with_the_core_fields(captured: io.StringIO) -> None:
    logging.getLogger("gully.test").info("hello %s", "world")
    line = last_line(captured)
    assert line["message"] == "hello world"
    assert line["level"] == "INFO"
    assert line["logger"] == "gully.test"
    assert str(line["ts"]).endswith("+00:00")
    assert "request_id" not in line


def test_the_request_id_is_attached_while_a_request_is_in_flight(captured: io.StringIO) -> None:
    token = request_id_ctx.set("req-123")
    try:
        logging.getLogger("gully.test").info("inside")
    finally:
        request_id_ctx.reset(token)
    assert last_line(captured)["request_id"] == "req-123"
    logging.getLogger("gully.test").info("outside")
    assert "request_id" not in last_line(captured)


def test_extra_fields_are_included_but_internals_are_not(captured: io.StringIO) -> None:
    logging.getLogger("gully.test").info("with extras", extra={"status": 201, "path": "/x"})
    line = last_line(captured)
    assert line["status"] == 201
    assert line["path"] == "/x"
    for internal in ("args", "msg", "levelno", "pathname", "created", "thread"):
        assert internal not in line


def test_exceptions_are_serialised_into_the_same_line(captured: io.StringIO) -> None:
    try:
        raise ValueError("kaboom")
    except ValueError:
        logging.getLogger("gully.test").exception("failed")
    line = last_line(captured)
    assert line["level"] == "ERROR"
    assert "ValueError: kaboom" in str(line["exception"])


def test_unserialisable_extras_do_not_break_logging(captured: io.StringIO) -> None:
    logging.getLogger("gully.test").info("odd", extra={"thing": object()})
    assert "object object" in str(last_line(captured)["thing"])


def test_configure_logging_sets_level_and_a_single_handler() -> None:
    root = logging.getLogger()
    saved_handlers, saved_level = root.handlers[:], root.level
    try:
        configure_logging("WARNING")
        configure_logging("WARNING")  # idempotent: no handler pile-up
        assert root.level == logging.WARNING
        assert len(root.handlers) == 1
        assert isinstance(root.handlers[0].formatter, JsonFormatter)
        assert logging.getLogger("sqlalchemy.engine").level == logging.WARNING
    finally:
        root.handlers[:] = saved_handlers
        root.setLevel(saved_level)


def test_uvicorn_access_lines_are_not_duplicated() -> None:
    root = logging.getLogger()
    saved_handlers, saved_level = root.handlers[:], root.level
    try:
        configure_logging("INFO")
        assert logging.getLogger("uvicorn.access").propagate is False
        assert logging.getLogger("uvicorn.error").propagate is True
    finally:
        root.handlers[:] = saved_handlers
        root.setLevel(saved_level)
