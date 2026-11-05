from __future__ import annotations

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, UTCDateTime


class RefreshToken(Base):
    """An opaque refresh token. Only its SHA-256 hash is stored."""

    __tablename__ = "refresh_tokens"
    __table_args__ = (
        sa.UniqueConstraint("token_hash"),
        sa.Index("ix_refresh_tokens_user_id", "user_id"),
        sa.Index("ix_refresh_tokens_family_id", "family_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    family_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, nullable=False)
    token_hash: Mapped[str] = mapped_column(sa.CHAR(64), nullable=False)
    issued_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
    rotated_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    revoked_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
