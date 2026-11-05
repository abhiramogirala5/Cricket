"""In-memory sliding-window rate limiter for /auth/*.

This is per process. Put a gateway or Redis-backed limiter in front when running more than one
replica (see docs/API_CONTRACT.md §7).
"""

from __future__ import annotations

import math
import time
from collections import deque
from collections.abc import Callable

from fastapi import Request

from app.core.config import Settings
from app.core.errors import rate_limited

_CLEANUP_THRESHOLD = 10_000


class SlidingWindowRateLimiter:
    def __init__(
        self,
        limit: int,
        window_seconds: int,
        *,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._limit = limit
        self._window = float(window_seconds)
        self._clock = clock
        self._hits: dict[str, deque[float]] = {}

    def check(self, key: str) -> int | None:
        """Record a hit. Returns ``None`` if allowed, otherwise seconds until a slot frees up."""
        now = self._clock()
        cutoff = now - self._window
        hits = self._hits.setdefault(key, deque())
        while hits and hits[0] <= cutoff:
            hits.popleft()
        if len(hits) >= self._limit:
            return max(1, math.ceil(hits[0] + self._window - now))
        hits.append(now)
        if len(self._hits) > _CLEANUP_THRESHOLD:
            self._purge(cutoff)
        return None

    def reset(self) -> None:
        self._hits.clear()

    def _purge(self, cutoff: float) -> None:
        for key in [k for k, q in self._hits.items() if not q or q[-1] <= cutoff]:
            del self._hits[key]


def client_ip(request: Request, settings: Settings) -> str:
    """Client address. ``X-Forwarded-For`` is used only when TRUSTED_PROXY is enabled and then the
    right-most entry (the one appended by our single trusted proxy) is taken."""
    if settings.trusted_proxy:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            parts = [p.strip() for p in forwarded.split(",") if p.strip()]
            if parts:
                return parts[-1]
    return request.client.host if request.client else "unknown"


async def enforce_auth_rate_limit(request: Request) -> None:
    """FastAPI dependency for the /auth router."""
    limiter: SlidingWindowRateLimiter = request.app.state.auth_rate_limiter
    settings: Settings = request.app.state.settings
    retry_after = limiter.check(client_ip(request, settings))
    if retry_after is not None:
        raise rate_limited(retry_after)
