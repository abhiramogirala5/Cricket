"""Replay clips: announce, complete, list, download and delete (owner-scoped)."""

from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import ApiError, not_found, payload_too_large, service_unavailable
from app.db.base import utcnow
from app.models.enums import ReplayStatus
from app.models.replay_clip import ReplayClip
from app.models.user import User
from app.schemas.common import Page
from app.schemas.replay import (
    DownloadTarget,
    ReplayCreate,
    ReplayCreated,
    ReplayRead,
    UploadTarget,
)
from app.services.storage import ObjectStorage, SignedUpload, StorageError

_STORAGE_DOWN = "The replay storage is temporarily unavailable. Try again in a moment."


def storage_path_for(owner_id: uuid.UUID, match_id: uuid.UUID, clip_id: uuid.UUID) -> str:
    """Where a replay lives in the bucket: one folder per owner, then per match."""
    return f"{owner_id}/{match_id}/{clip_id}.gur"


def _upload_target(upload: SignedUpload) -> UploadTarget:
    return UploadTarget(
        url=upload.url,
        method="PUT",
        headers=dict(upload.headers or {}),
        expires_in_seconds=upload.expires_in_seconds,
    )


async def _owned(session: AsyncSession, owner_id: uuid.UUID, clip_id: uuid.UUID) -> ReplayClip:
    clip = await session.get(ReplayClip, clip_id)
    if clip is None or clip.owner_id != owner_id:
        raise not_found("Replay not found.")
    return clip


async def create_clip(
    session: AsyncSession,
    storage: ObjectStorage,
    settings: Settings,
    user: User,
    data: ReplayCreate,
) -> ReplayCreated:
    """Record the announcement and hand out an upload link (unless the file is already stored)."""
    if data.size_bytes > settings.replay_max_bytes:
        raise payload_too_large(settings.replay_max_bytes)
    clip = await session.get(ReplayClip, data.id)
    if clip is not None and clip.owner_id != user.id:
        raise ApiError(409, "CONFLICT", "This replay id is already in use.")
    if clip is None:
        clip = ReplayClip(
            id=data.id,
            owner_id=user.id,
            match_id=data.match_id,
            storage_path=storage_path_for(user.id, data.match_id, data.id),
            status=ReplayStatus.PENDING.value,
        )
        session.add(clip)
    elif clip.status == ReplayStatus.READY.value:
        # Already stored: a delivery id that was unknown the first time may be known now.
        if data.delivery_id is not None and clip.delivery_id is None:
            clip.delivery_id = data.delivery_id
            await session.commit()
        return ReplayCreated(replay=ReplayRead.model_validate(clip), upload=None)
    clip.delivery_id = data.delivery_id
    clip.size_bytes = data.size_bytes
    clip.sha256 = data.sha256
    clip.width = data.width
    clip.height = data.height
    clip.frame_count = data.frame_count
    clip.duration_ms = data.duration_ms
    await session.commit()
    try:
        upload = await storage.create_upload(clip.storage_path)
    except StorageError as error:
        raise service_unavailable(_STORAGE_DOWN) from error
    return ReplayCreated(replay=ReplayRead.model_validate(clip), upload=_upload_target(upload))


async def complete_clip(
    session: AsyncSession, storage: ObjectStorage, user: User, clip_id: uuid.UUID
) -> ReplayRead:
    """Mark the replay stored, after checking that the file is really in the bucket."""
    clip = await _owned(session, user.id, clip_id)
    if clip.status == ReplayStatus.READY.value:
        return ReplayRead.model_validate(clip)
    try:
        size = await storage.object_size(clip.storage_path)
    except StorageError as error:
        raise service_unavailable(_STORAGE_DOWN) from error
    if size is None:
        raise ApiError(409, "UPLOAD_MISSING", "The replay file has not been uploaded yet.")
    if size != clip.size_bytes:
        raise ApiError(
            409,
            "UPLOAD_SIZE_MISMATCH",
            "The uploaded file is not the size that was announced. Upload it again.",
        )
    clip.status = ReplayStatus.READY.value
    clip.uploaded_at = utcnow()
    await session.commit()
    return ReplayRead.model_validate(clip)


async def list_clips(
    session: AsyncSession,
    user: User,
    *,
    delivery_id: uuid.UUID | None,
    match_id: uuid.UUID | None,
    limit: int,
    offset: int,
) -> Page[ReplayRead]:
    """Stored replays of the user, newest first."""
    conditions = [
        ReplayClip.owner_id == user.id,
        ReplayClip.status == ReplayStatus.READY.value,
    ]
    if delivery_id is not None:
        conditions.append(ReplayClip.delivery_id == delivery_id)
    if match_id is not None:
        conditions.append(ReplayClip.match_id == match_id)
    total = await session.scalar(select(func.count()).select_from(ReplayClip).where(*conditions))
    rows = await session.scalars(
        select(ReplayClip)
        .where(*conditions)
        .order_by(ReplayClip.created_at.desc(), ReplayClip.id)
        .limit(limit)
        .offset(offset)
    )
    return Page[ReplayRead](
        items=[ReplayRead.model_validate(row) for row in rows],
        total=total or 0,
        limit=limit,
        offset=offset,
    )


async def download_target(
    session: AsyncSession,
    storage: ObjectStorage,
    settings: Settings,
    user: User,
    clip_id: uuid.UUID,
) -> DownloadTarget:
    clip = await _owned(session, user.id, clip_id)
    if clip.status != ReplayStatus.READY.value:
        raise not_found("Replay not found.")
    try:
        url = await storage.create_download_url(
            clip.storage_path, settings.replay_download_ttl_seconds
        )
    except StorageError as error:
        raise service_unavailable(_STORAGE_DOWN) from error
    return DownloadTarget(url=url, expires_in_seconds=settings.replay_download_ttl_seconds)


async def delete_clip(
    session: AsyncSession, storage: ObjectStorage, user: User, clip_id: uuid.UUID
) -> None:
    clip = await _owned(session, user.id, clip_id)
    try:
        await storage.delete(clip.storage_path)
    except StorageError as error:
        raise service_unavailable(_STORAGE_DOWN) from error
    await session.delete(clip)
    await session.commit()


async def storage_paths_of(session: AsyncSession, owner_id: uuid.UUID) -> list[str]:
    """Every replay path of a user (used to clean the bucket when an account is deleted)."""
    rows = await session.scalars(
        select(ReplayClip.storage_path).where(ReplayClip.owner_id == owner_id)
    )
    return list(rows)
