"""Sliding-window limiter and client address detection."""

from __future__ import annotations

import pytest
from starlette.requests import Request

from app.core import rate_limit
from app.core.rate_limit import SlidingWindowRateLimiter, client_ip
from tests.conftest import make_settings


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def make_request(
    forwarded: str | None = None, client: tuple[str, int] | None = ("9.9.9.9", 1)
) -> Request:
    headers = [(b"x-forwarded-for", forwarded.encode())] if forwarded is not None else []
    scope = {"type": "http", "method": "GET", "path": "/", "headers": headers, "client": client}
    return Request(scope)


# ---------------------------------------------------------------------------- limiter


def test_allows_up_to_the_limit_then_blocks() -> None:
    limiter = SlidingWindowRateLimiter(3, 60, clock=FakeClock())
    assert [limiter.check("a") for _ in range(3)] == [None, None, None]
    assert limiter.check("a") == 60


def test_the_window_slides_and_retry_after_counts_down() -> None:
    clock = FakeClock()
    limiter = SlidingWindowRateLimiter(2, 60, clock=clock)
    assert limiter.check("a") is None  # t = 0
    clock.now += 20
    assert limiter.check("a") is None  # t = 20
    clock.now += 10
    assert limiter.check("a") == 30  # oldest hit leaves the window at t = 60
    clock.now += 30.5
    assert limiter.check("a") is None  # first hit expired, a slot is free again
    assert limiter.check("a") is not None  # but only one


def test_a_blocked_attempt_is_not_counted() -> None:
    clock = FakeClock()
    limiter = SlidingWindowRateLimiter(1, 10, clock=clock)
    assert limiter.check("a") is None
    for _ in range(5):
        assert limiter.check("a") is not None  # hammering does not extend the block
    clock.now += 10.1
    assert limiter.check("a") is None


def test_keys_are_independent_and_reset_clears_everything() -> None:
    limiter = SlidingWindowRateLimiter(1, 60, clock=FakeClock())
    assert limiter.check("a") is None
    assert limiter.check("b") is None
    assert limiter.check("a") is not None
    limiter.reset()
    assert limiter.check("a") is None


def test_stale_keys_are_purged_when_the_table_grows(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(rate_limit, "_CLEANUP_THRESHOLD", 3)
    clock = FakeClock()
    limiter = SlidingWindowRateLimiter(5, 10, clock=clock)
    for key in ("a", "b", "c"):
        limiter.check(key)
    clock.now += 100  # all of the above are stale now
    limiter.check("d")
    limiter.check("e")  # 5 keys > threshold: the stale ones are dropped
    assert set(limiter._hits) == {"d", "e"}


# ---------------------------------------------------------------------------- client_ip


def test_forwarded_header_is_ignored_unless_the_proxy_is_trusted() -> None:
    settings = make_settings(trusted_proxy=False)
    assert client_ip(make_request("1.1.1.1"), settings) == "9.9.9.9"


def test_trusted_proxy_uses_the_rightmost_forwarded_entry() -> None:
    settings = make_settings(trusted_proxy=True)
    # A client can prepend fake addresses; only the entry our own proxy appended counts.
    assert client_ip(make_request("6.6.6.6, 1.1.1.1, 2.2.2.2"), settings) == "2.2.2.2"
    assert client_ip(make_request("  3.3.3.3  "), settings) == "3.3.3.3"


@pytest.mark.parametrize("header", [None, "", " , ,"])
def test_trusted_proxy_without_a_usable_header_falls_back_to_the_socket(header: str | None) -> None:
    assert client_ip(make_request(header), make_settings(trusted_proxy=True)) == "9.9.9.9"


def test_unknown_when_there_is_no_client_address() -> None:
    assert client_ip(make_request(client=None), make_settings()) == "unknown"
