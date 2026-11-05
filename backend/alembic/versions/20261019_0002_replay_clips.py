"""Replay clips (files in Supabase Storage) and row-level security on every table.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-19

Written to match ``app.models`` exactly (checked by tests/db/test_migrations.py). It deliberately
imports nothing from the application so that it keeps working when the models change later.

Row-level security (PostgreSQL only): Supabase publishes every table of the ``public`` schema
through its REST "Data API", readable and writable with the project's public ``anon`` key unless
row-level security is switched on. This API reaches the database as the table owner, which is not
subject to row-level security, so enabling it without policies closes the Data API completely
without affecting the application.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Every table of this application (``replay_clips`` is created below).
_TABLES = (
    "users",
    "refresh_tokens",
    "sync_events",
    "players",
    "teams",
    "matches",
    "innings",
    "match_players",
    "match_rules",
    "scene_scans",
    "tosses",
    "wicket_detections",
    "deliveries",
    "delivery_decisions",
    "trajectory_snapshots",
    "replay_clips",
)


def upgrade() -> None:
    op.create_table(
        "replay_clips",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("match_id", sa.Uuid(), nullable=False),
        sa.Column("delivery_id", sa.Uuid(), nullable=True),
        sa.Column("storage_path", sa.String(length=200), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=True),
        sa.Column("width", sa.Integer(), nullable=True),
        sa.Column("height", sa.Integer(), nullable=True),
        sa.Column("frame_count", sa.Integer(), nullable=True),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(length=10), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("uploaded_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "duration_ms IS NULL OR (duration_ms BETWEEN 0 AND 60000)",
            name=op.f("ck_replay_clips_duration_range"),
        ),
        sa.CheckConstraint(
            "frame_count IS NULL OR (frame_count BETWEEN 1 AND 600)",
            name=op.f("ck_replay_clips_frame_count_range"),
        ),
        sa.CheckConstraint(
            "height IS NULL OR (height BETWEEN 1 AND 65535)",
            name=op.f("ck_replay_clips_height_range"),
        ),
        sa.CheckConstraint("size_bytes > 0", name=op.f("ck_replay_clips_size_bytes_positive")),
        sa.CheckConstraint(
            "status IN ('PENDING','READY')", name=op.f("ck_replay_clips_status_valid")
        ),
        sa.CheckConstraint(
            "width IS NULL OR (width BETWEEN 1 AND 65535)",
            name=op.f("ck_replay_clips_width_range"),
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_replay_clips_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_replay_clips")),
        sa.UniqueConstraint("storage_path", name=op.f("uq_replay_clips_storage_path")),
    )
    op.create_index(
        "ix_replay_clips_owner_id_delivery_id",
        "replay_clips",
        ["owner_id", "delivery_id"],
        unique=False,
    )
    op.create_index(
        "ix_replay_clips_owner_id_match_id", "replay_clips", ["owner_id", "match_id"], unique=False
    )

    if op.get_bind().dialect.name == "postgresql":
        for table in _TABLES:
            op.execute(f'ALTER TABLE "{table}" ENABLE ROW LEVEL SECURITY')


def downgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        for table in _TABLES:
            if table != "replay_clips":
                op.execute(f'ALTER TABLE "{table}" DISABLE ROW LEVEL SECURITY')
    op.drop_index("ix_replay_clips_owner_id_match_id", table_name="replay_clips")
    op.drop_index("ix_replay_clips_owner_id_delivery_id", table_name="replay_clips")
    op.drop_table("replay_clips")
