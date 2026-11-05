"""Unversioned health endpoints (API_CONTRACT §2)."""

from __future__ import annotations

import logging

from fastapi import APIRouter
from sqlalchemy import text

from app.api.deps import SessionDep
from app.core.errors import service_unavailable
from app.schemas.common import HealthReady, StatusOk

router = APIRouter(tags=["health"])
_log = logging.getLogger(__name__)


@router.get("/health", response_model=StatusOk, summary="Liveness probe")
async def health() -> StatusOk:
    return StatusOk(status="ok")


@router.get(
    "/health/ready", response_model=HealthReady, summary="Readiness probe (checks the database)"
)
async def health_ready(session: SessionDep) -> HealthReady:
    try:
        await session.execute(text("SELECT 1"))
    except Exception as exc:
        _log.warning("Readiness check failed: %s", type(exc).__name__)
        raise service_unavailable("The database is not reachable.") from exc
    return HealthReady(status="ready", database="ok")
