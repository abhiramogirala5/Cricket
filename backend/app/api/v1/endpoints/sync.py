"""POST /sync/push (API_CONTRACT §5)."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import CurrentUser, SessionDep
from app.schemas.sync import SyncPushRequest, SyncPushResponse
from app.services.sync import push_events

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("/push", response_model=SyncPushResponse)
async def push(body: SyncPushRequest, user: CurrentUser, session: SessionDep) -> SyncPushResponse:
    return await push_events(session, user.id, body.events)
