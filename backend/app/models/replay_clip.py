from __future__ import annotations

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, UTCDateTime, in_check, utcnow
from app.models.enums import ReplayStatus


class ReplayClip(Base):
    """The replay file of one delivery (the file itself lives in Supabase Storage).

    The row is created before the upload (``PENDING``) and becomes ``READY`` once the server has
    seen the object in the bucket with the announced size. ``match_id`` and ``delivery_id`` are the
    client's ids and deliberately have no foreign key: the phone uploads in the background and the
    match or delivery may not have been synced yet when the replay arrives.
    """

    __tablename__ = "replay_clips"
    __table_args__ = (
        sa.CheckConstraint("size_bytes > 0", name="size_bytes_positive"),
        sa.CheckConstraint(in_check("status", ReplayStatus), name="status_valid"),
        sa.CheckConstraint("width IS NULL OR (width BETWEEN 1 AND 65535)", name="width_range"),
        sa.CheckConstraint("height IS NULL OR (height BETWEEN 1 AND 65535)", name="height_range"),
        sa.CheckConstraint(
            "frame_count IS NULL OR (frame_count BETWEEN 1 AND 600)", name="frame_count_range"
        ),
        sa.CheckConstraint(
            "duration_ms IS NULL OR (duration_ms BETWEEN 0 AND 60000)", name="duration_range"
        ),
        sa.Index("ix_replay_clips_owner_id_delivery_id", "owner_id", "delivery_id"),
        sa.Index("ix_replay_clips_owner_id_match_id", "owner_id", "match_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True)
    owner_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    match_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, nullable=False)
    delivery_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    storage_path: Mapped[str] = mapped_column(sa.String(200), nullable=False, unique=True)
    size_bytes: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    sha256: Mapped[str | None] = mapped_column(sa.String(64))
    width: Mapped[int | None] = mapped_column(sa.Integer)
    height: Mapped[int | None] = mapped_column(sa.Integer)
    frame_count: Mapped[int | None] = mapped_column(sa.Integer)
    duration_ms: Mapped[int | None] = mapped_column(sa.Integer)
    status: Mapped[str] = mapped_column(
        sa.String(10), nullable=False, default=ReplayStatus.PENDING.value
    )
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utcnow)
    uploaded_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
