"""Replay clips: signed upload and download links for the replay of a delivery (API_CONTRACT §8)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, Limit, Offset, SessionDep, SettingsDep, StorageDep
from app.schemas.common import Page
from app.schemas.replay import DownloadTarget, ReplayCreate, ReplayCreated, ReplayRead
from app.services import replay_service

router = APIRouter(prefix="/replays", tags=["replays"])


@router.post("", response_model=ReplayCreated, status_code=status.HTTP_201_CREATED)
async def announce_replay(
    body: ReplayCreate,
    *,
    response: Response,
    user: CurrentUser,
    session: SessionDep,
    settings: SettingsDep,
    storage: StorageDep,
) -> ReplayCreated:
    created = await replay_service.create_clip(session, storage, settings, user, body)
    if created.upload is None:
        response.status_code = status.HTTP_200_OK
    return created


@router.post("/{replay_id}/complete", response_model=ReplayRead)
async def complete_replay(
    replay_id: uuid.UUID, user: CurrentUser, session: SessionDep, storage: StorageDep
) -> ReplayRead:
    return await replay_service.complete_clip(session, storage, user, replay_id)


@router.get("", response_model=Page[ReplayRead])
async def list_replays(
    *,
    user: CurrentUser,
    session: SessionDep,
    delivery_id: Annotated[uuid.UUID | None, Query(description="Only this delivery")] = None,
    match_id: Annotated[uuid.UUID | None, Query(description="Only this match")] = None,
    limit: Limit = 50,
    offset: Offset = 0,
) -> Page[ReplayRead]:
    return await replay_service.list_clips(
        session, user, delivery_id=delivery_id, match_id=match_id, limit=limit, offset=offset
    )


@router.get("/{replay_id}/download", response_model=DownloadTarget)
async def download_replay(
    replay_id: uuid.UUID,
    user: CurrentUser,
    session: SessionDep,
    settings: SettingsDep,
    storage: StorageDep,
) -> DownloadTarget:
    return await replay_service.download_target(session, storage, settings, user, replay_id)


@router.delete("/{replay_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_replay(
    replay_id: uuid.UUID, user: CurrentUser, session: SessionDep, storage: StorageDep
) -> Response:
    await replay_service.delete_clip(session, storage, user, replay_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
