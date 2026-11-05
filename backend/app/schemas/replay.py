"""Request and response models of the replay endpoints (API_CONTRACT §8)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import Field

from app.models.enums import ReplayStatus
from app.schemas.common import ApiModel, RequestModel


class ReplayCreate(RequestModel):
    """Announces a replay file that the phone is about to upload.

    ``id`` is made by the phone, so announcing the same replay twice (a retry after a lost
    answer) is harmless.
    """

    id: uuid.UUID
    match_id: uuid.UUID
    delivery_id: uuid.UUID | None = None
    size_bytes: int = Field(ge=1)
    sha256: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")
    width: int | None = Field(default=None, ge=1, le=65535)
    height: int | None = Field(default=None, ge=1, le=65535)
    frame_count: int | None = Field(default=None, ge=1, le=600)
    duration_ms: int | None = Field(default=None, ge=0, le=60000)


class ReplayRead(ApiModel):
    id: uuid.UUID
    match_id: uuid.UUID
    delivery_id: uuid.UUID | None
    size_bytes: int
    sha256: str | None
    width: int | None
    height: int | None
    frame_count: int | None
    duration_ms: int | None
    status: ReplayStatus
    created_at: datetime
    uploaded_at: datetime | None


class UploadTarget(ApiModel):
    """Send the file with this request: ``PUT url`` with ``headers`` and the file as the body."""

    url: str
    method: Literal["PUT"] = "PUT"
    headers: dict[str, str]
    expires_in_seconds: int


class ReplayCreated(ApiModel):
    replay: ReplayRead
    # Absent when the replay is already stored.
    upload: UploadTarget | None


class DownloadTarget(ApiModel):
    url: str
    expires_in_seconds: int
