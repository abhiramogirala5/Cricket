"""POST /sync/push processing (API_CONTRACT §5.1-5.2).

Events are applied strictly in array order. Each one runs inside its own SAVEPOINT together with
its idempotency-ledger row: a rejected event rolls back only itself and is *not* recorded, so the
client may fix the cause and re-send the same ``event_id``.
"""

from __future__ import annotations

import json
import logging
import uuid
from collections.abc import Sequence
from datetime import datetime

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import utcnow
from app.models.enums import EntityType, SyncAction, SyncStatus
from app.models.sync_event import SyncEvent
from app.schemas.sync import (
    PayloadModel,
    SyncEventError,
    SyncEventIn,
    SyncEventResult,
    SyncPushResponse,
)
from app.services.sync.context import SyncContext
from app.services.sync.errors import (
    INTERNAL_ERROR,
    INVALID_PAYLOAD,
    UNSUPPORTED_EVENT,
    SyncRejection,
)
from app.services.sync.registry import ROUTES, Route

_log = logging.getLogger(__name__)
_MAX_MESSAGE_LENGTH = 300


def _result(
    event_id: uuid.UUID, status: SyncStatus, rejection: SyncRejection | None = None
) -> SyncEventResult:
    error = SyncEventError(code=rejection.code, message=rejection.message) if rejection else None
    return SyncEventResult(event_id=event_id, status=status, error=error)


def _resolve_route(event: SyncEventIn) -> tuple[EntityType, SyncAction, Route]:
    try:
        entity = EntityType(event.entity_type)
    except ValueError as exc:
        raise SyncRejection(
            UNSUPPORTED_EVENT, f"unknown entity_type {event.entity_type!r}"
        ) from exc
    try:
        action = SyncAction(event.action)
    except ValueError as exc:
        raise SyncRejection(UNSUPPORTED_EVENT, f"unknown action {event.action!r}") from exc
    route = ROUTES.get((entity, action))
    if route is None:
        raise SyncRejection(
            UNSUPPORTED_EVENT, f"action {action.value} is not supported for {entity.value}"
        )
    return entity, action, route


def _parse_payload(route: Route, payload: dict[str, object]) -> PayloadModel:
    """Validate in JSON mode so strict typing applies ("3" is not an int, 1 is not a bool)."""
    try:
        return route.schema.model_validate_json(json.dumps(payload))
    except ValidationError as exc:
        parts = []
        for item in exc.errors()[:5]:
            location = ".".join(str(part) for part in item["loc"]) or "payload"
            parts.append(f"{location}: {item['msg']}")
        message = "; ".join(parts)[:_MAX_MESSAGE_LENGTH]
        raise SyncRejection(INVALID_PAYLOAD, message) from exc
    except (TypeError, ValueError) as exc:
        raise SyncRejection(INVALID_PAYLOAD, "payload is not valid JSON") from exc


async def _already_applied(session: AsyncSession, owner_id: uuid.UUID, event_id: uuid.UUID) -> bool:
    found = await session.scalar(
        select(SyncEvent.event_id).where(
            SyncEvent.owner_id == owner_id, SyncEvent.event_id == event_id
        )
    )
    return found is not None


async def _process_event(
    session: AsyncSession, owner_id: uuid.UUID, event: SyncEventIn, now: datetime
) -> SyncEventResult:
    if await _already_applied(session, owner_id, event.event_id):
        return _result(event.event_id, SyncStatus.DUPLICATE)

    try:
        entity, action, route = _resolve_route(event)
        payload = _parse_payload(route, event.payload)
        ctx = SyncContext(session=session, owner_id=owner_id, now=now)
        async with session.begin_nested():
            await route.handler(ctx, payload)
            session.add(
                SyncEvent(
                    owner_id=owner_id,
                    event_id=event.event_id,
                    entity_type=entity.value,
                    action=action.value,
                    applied_at=now,
                )
            )
    except SyncRejection as rejection:
        return _result(event.event_id, SyncStatus.REJECTED, rejection)
    except IntegrityError:
        # Most likely a concurrent request applied this very event first.
        if await _already_applied(session, owner_id, event.event_id):
            return _result(event.event_id, SyncStatus.DUPLICATE)
        _log.exception(
            "Integrity error while applying sync event",
            extra={"entity_type": event.entity_type, "sync_action": event.action},
        )
        return _result(
            event.event_id,
            SyncStatus.REJECTED,
            SyncRejection(INTERNAL_ERROR, "the event could not be applied; retry later"),
        )
    except Exception:
        _log.exception(
            "Unexpected error while applying sync event",
            extra={"entity_type": event.entity_type, "sync_action": event.action},
        )
        return _result(
            event.event_id,
            SyncStatus.REJECTED,
            SyncRejection(INTERNAL_ERROR, "the event could not be applied; retry later"),
        )
    return _result(event.event_id, SyncStatus.APPLIED)


async def push_events(
    session: AsyncSession, owner_id: uuid.UUID, events: Sequence[SyncEventIn]
) -> SyncPushResponse:
    now = utcnow()
    results = [await _process_event(session, owner_id, event, now) for event in events]
    await session.commit()
    return SyncPushResponse(results=results, server_time=utcnow())
