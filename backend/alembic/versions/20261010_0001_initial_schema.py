"""Initial schema: accounts, roster, matches, scoring, AI evidence and the sync ledger.

Revision ID: 0001
Revises:
Create Date: 2026-10-10

Written to match ``app.models`` exactly (checked by tests/db/test_migrations.py). It deliberately
imports nothing from the application so that it keeps working when the models change later.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# JSON on every dialect, JSONB on PostgreSQL (mirrors app.db.base.JSONType).
JSON_DOCUMENT = sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql")


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("display_name", sa.String(length=100), nullable=False),
        sa.Column("phone", sa.String(length=25), nullable=True),
        sa.Column("avatar_url", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_users")),
        sa.UniqueConstraint("email", name=op.f("uq_users_email")),
    )
    op.create_table(
        "players",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("display_name", sa.String(length=100), nullable=False),
        sa.Column("batting_hand", sa.String(length=10), server_default="UNKNOWN", nullable=False),
        sa.Column("declared_height_cm", sa.SmallInteger(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "batting_hand IN ('LEFT','RIGHT','UNKNOWN')", name=op.f("ck_players_batting_hand_valid")
        ),
        sa.CheckConstraint(
            "declared_height_cm IS NULL OR (declared_height_cm BETWEEN 100 AND 230)",
            name=op.f("ck_players_declared_height_range"),
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"], ["users.id"], name=op.f("fk_players_owner_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_players")),
    )
    op.create_index("ix_players_owner_id", "players", ["owner_id"], unique=False)
    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("token_hash", sa.CHAR(length=64), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("rotated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_refresh_tokens_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_refresh_tokens")),
        sa.UniqueConstraint("token_hash", name=op.f("uq_refresh_tokens_token_hash")),
    )
    op.create_index("ix_refresh_tokens_family_id", "refresh_tokens", ["family_id"], unique=False)
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"], unique=False)
    op.create_table(
        "sync_events",
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("event_id", sa.Uuid(), nullable=False),
        sa.Column("entity_type", sa.String(length=30), nullable=False),
        sa.Column("action", sa.String(length=10), nullable=False),
        sa.Column("applied_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_sync_events_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("owner_id", "event_id", name=op.f("pk_sync_events")),
    )
    op.create_table(
        "teams",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["owner_id"], ["users.id"], name=op.f("fk_teams_owner_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_teams")),
    )
    op.create_index("ix_teams_owner_id", "teams", ["owner_id"], unique=False)
    op.create_table(
        "matches",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("team_a_id", sa.Uuid(), nullable=False),
        sa.Column("team_b_id", sa.Uuid(), nullable=False),
        sa.Column("match_name", sa.String(length=150), nullable=True),
        sa.Column("location_name", sa.String(length=255), nullable=True),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=20), server_default="DRAFT", nullable=False),
        sa.Column("overs_per_innings", sa.SmallInteger(), server_default="6", nullable=False),
        sa.Column(
            "local_rules_profile",
            sa.String(length=40),
            server_default="CASUAL_GULLY",
            nullable=False,
        ),
        sa.Column("winner_team_id", sa.Uuid(), nullable=True),
        sa.Column("result_summary", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "status IN ('DRAFT','SCANNING','READY','LIVE','COMPLETED','ABANDONED')",
            name=op.f("ck_matches_status_valid"),
        ),
        sa.CheckConstraint(
            "overs_per_innings BETWEEN 1 AND 50", name=op.f("ck_matches_overs_range")
        ),
        sa.CheckConstraint("team_a_id <> team_b_id", name=op.f("ck_matches_teams_differ")),
        sa.ForeignKeyConstraint(
            ["owner_id"], ["users.id"], name=op.f("fk_matches_owner_id_users"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["team_a_id"], ["teams.id"], name=op.f("fk_matches_team_a_id_teams")
        ),
        sa.ForeignKeyConstraint(
            ["team_b_id"], ["teams.id"], name=op.f("fk_matches_team_b_id_teams")
        ),
        sa.ForeignKeyConstraint(
            ["winner_team_id"], ["teams.id"], name=op.f("fk_matches_winner_team_id_teams")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_matches")),
    )
    op.create_index(
        "ix_matches_owner_id_created_at", "matches", ["owner_id", "created_at"], unique=False
    )
    op.create_index("ix_matches_status", "matches", ["status"], unique=False)
    op.create_table(
        "innings",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("match_id", sa.Uuid(), nullable=False),
        sa.Column("innings_number", sa.SmallInteger(), nullable=False),
        sa.Column("batting_team_id", sa.Uuid(), nullable=False),
        sa.Column("bowling_team_id", sa.Uuid(), nullable=False),
        sa.Column("total_runs", sa.Integer(), server_default="0", nullable=False),
        sa.Column("wickets", sa.Integer(), server_default="0", nullable=False),
        sa.Column("legal_balls", sa.Integer(), server_default="0", nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "batting_team_id <> bowling_team_id", name=op.f("ck_innings_teams_differ")
        ),
        sa.CheckConstraint(
            "innings_number BETWEEN 1 AND 4", name=op.f("ck_innings_innings_number_range")
        ),
        sa.ForeignKeyConstraint(
            ["batting_team_id"], ["teams.id"], name=op.f("fk_innings_batting_team_id_teams")
        ),
        sa.ForeignKeyConstraint(
            ["bowling_team_id"], ["teams.id"], name=op.f("fk_innings_bowling_team_id_teams")
        ),
        sa.ForeignKeyConstraint(
            ["match_id"],
            ["matches.id"],
            name=op.f("fk_innings_match_id_matches"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_innings")),
        sa.UniqueConstraint(
            "match_id", "innings_number", name=op.f("uq_innings_match_id_innings_number")
        ),
    )
    op.create_table(
        "match_players",
        sa.Column("match_id", sa.Uuid(), nullable=False),
        sa.Column("player_id", sa.Uuid(), nullable=False),
        sa.Column("team_id", sa.Uuid(), nullable=False),
        sa.Column("batting_hand", sa.String(length=10), server_default="UNKNOWN", nullable=False),
        sa.Column("declared_height_cm", sa.SmallInteger(), nullable=True),
        sa.Column("batting_order", sa.SmallInteger(), nullable=True),
        sa.Column("is_captain", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("is_wicketkeeper", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.CheckConstraint(
            "batting_hand IN ('LEFT','RIGHT','UNKNOWN')",
            name=op.f("ck_match_players_batting_hand_valid"),
        ),
        sa.CheckConstraint(
            "batting_order IS NULL OR (batting_order BETWEEN 1 AND 30)",
            name=op.f("ck_match_players_batting_order_range"),
        ),
        sa.CheckConstraint(
            "declared_height_cm IS NULL OR (declared_height_cm BETWEEN 100 AND 230)",
            name=op.f("ck_match_players_declared_height_range"),
        ),
        sa.ForeignKeyConstraint(
            ["match_id"],
            ["matches.id"],
            name=op.f("fk_match_players_match_id_matches"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["player_id"], ["players.id"], name=op.f("fk_match_players_player_id_players")
        ),
        sa.ForeignKeyConstraint(
            ["team_id"], ["teams.id"], name=op.f("fk_match_players_team_id_teams")
        ),
        sa.PrimaryKeyConstraint("match_id", "player_id", name=op.f("pk_match_players")),
    )
    op.create_index("ix_match_players_player_id", "match_players", ["player_id"], unique=False)
    op.create_table(
        "match_rules",
        sa.Column("match_id", sa.Uuid(), nullable=False),
        sa.Column("wide_enabled", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("no_ball_enabled", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column(
            "front_foot_no_ball_enabled",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
        sa.Column(
            "edge_review_enabled", sa.Boolean(), server_default=sa.text("true"), nullable=False
        ),
        sa.Column(
            "lbw_review_enabled", sa.Boolean(), server_default=sa.text("true"), nullable=False
        ),
        sa.Column(
            "full_toss_above_waist_is_no_ball",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
        sa.Column(
            "bounced_above_shoulder_is_no_ball",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
        sa.Column("max_bouncers_per_over", sa.SmallInteger(), nullable=True),
        sa.Column(
            "lateral_reach_multiplier",
            sa.Numeric(precision=4, scale=2, asdecimal=False),
            server_default="0.60",
            nullable=False,
        ),
        sa.CheckConstraint(
            "lateral_reach_multiplier BETWEEN 0.20 AND 1.50",
            name=op.f("ck_match_rules_lateral_reach_range"),
        ),
        sa.CheckConstraint(
            "max_bouncers_per_over IS NULL OR (max_bouncers_per_over BETWEEN 0 AND 6)",
            name=op.f("ck_match_rules_max_bouncers_range"),
        ),
        sa.ForeignKeyConstraint(
            ["match_id"],
            ["matches.id"],
            name=op.f("fk_match_rules_match_id_matches"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("match_id", name=op.f("pk_match_rules")),
    )
    op.create_table(
        "scene_scans",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("match_id", sa.Uuid(), nullable=False),
        sa.Column("camera_device_model", sa.String(length=150), nullable=True),
        sa.Column("capture_fps", sa.SmallInteger(), nullable=True),
        sa.Column("scan_duration_ms", sa.Integer(), nullable=False),
        sa.Column("ground_plane", JSON_DOCUMENT, nullable=True),
        sa.Column("pitch_direction", JSON_DOCUMENT, nullable=True),
        sa.Column("batsman_plane", JSON_DOCUMENT, nullable=True),
        sa.Column(
            "overall_confidence", sa.Numeric(precision=4, scale=3, asdecimal=False), nullable=False
        ),
        sa.Column("model_version", sa.String(length=100), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "capture_fps IS NULL OR (capture_fps BETWEEN 1 AND 240)",
            name=op.f("ck_scene_scans_capture_fps_range"),
        ),
        sa.CheckConstraint(
            "overall_confidence BETWEEN 0 AND 1",
            name=op.f("ck_scene_scans_overall_confidence_range"),
        ),
        sa.CheckConstraint(
            "scan_duration_ms >= 0", name=op.f("ck_scene_scans_scan_duration_non_negative")
        ),
        sa.ForeignKeyConstraint(
            ["match_id"],
            ["matches.id"],
            name=op.f("fk_scene_scans_match_id_matches"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_scene_scans")),
    )
    op.create_index("ix_scene_scans_match_id", "scene_scans", ["match_id"], unique=False)
    op.create_table(
        "tosses",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("match_id", sa.Uuid(), nullable=False),
        sa.Column("called_by_player_id", sa.Uuid(), nullable=True),
        sa.Column("call_choice", sa.String(length=10), nullable=False),
        sa.Column("result", sa.String(length=10), nullable=False),
        sa.Column("winner_team_id", sa.Uuid(), nullable=True),
        sa.Column("winner_decision", sa.String(length=10), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "call_choice IN ('HEADS','TAILS')", name=op.f("ck_tosses_call_choice_valid")
        ),
        sa.CheckConstraint("result IN ('HEADS','TAILS')", name=op.f("ck_tosses_result_valid")),
        sa.CheckConstraint(
            "winner_decision IS NULL OR winner_decision IN ('BAT','BOWL')",
            name=op.f("ck_tosses_winner_decision_valid"),
        ),
        sa.ForeignKeyConstraint(
            ["called_by_player_id"],
            ["players.id"],
            name=op.f("fk_tosses_called_by_player_id_players"),
        ),
        sa.ForeignKeyConstraint(
            ["match_id"],
            ["matches.id"],
            name=op.f("fk_tosses_match_id_matches"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["winner_team_id"], ["teams.id"], name=op.f("fk_tosses_winner_team_id_teams")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_tosses")),
        sa.UniqueConstraint("match_id", name=op.f("uq_tosses_match_id")),
    )
    op.create_table(
        "wicket_detections",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("match_id", sa.Uuid(), nullable=False),
        sa.Column("scene_scan_id", sa.Uuid(), nullable=True),
        sa.Column("wicket_family", sa.String(length=40), nullable=False),
        sa.Column("bounding_box", JSON_DOCUMENT, nullable=False),
        sa.Column("target_polygon", JSON_DOCUMENT, nullable=False),
        sa.Column("target_plane", JSON_DOCUMENT, nullable=True),
        sa.Column("ground_contact_line", JSON_DOCUMENT, nullable=True),
        sa.Column(
            "object_confidence", sa.Numeric(precision=4, scale=3, asdecimal=False), nullable=False
        ),
        sa.Column(
            "temporal_stability", sa.Numeric(precision=4, scale=3, asdecimal=False), nullable=False
        ),
        sa.Column(
            "context_confidence", sa.Numeric(precision=4, scale=3, asdecimal=False), nullable=False
        ),
        sa.Column(
            "final_confidence", sa.Numeric(precision=4, scale=3, asdecimal=False), nullable=False
        ),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("model_version", sa.String(length=100), nullable=False),
        sa.Column("detected_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "wicket_family IN ('TRADITIONAL_STUMPS','CHAIR','BRICK_STACK','BOTTLE_STACK','CONE_STACK','BUCKET','BAG_OR_OBJECT','WALL_TARGET','UNKNOWN_PHYSICAL_OBJECT')",
            name=op.f("ck_wicket_detections_wicket_family_valid"),
        ),
        sa.CheckConstraint(
            "context_confidence BETWEEN 0 AND 1",
            name=op.f("ck_wicket_detections_context_confidence_range"),
        ),
        sa.CheckConstraint(
            "final_confidence BETWEEN 0 AND 1",
            name=op.f("ck_wicket_detections_final_confidence_range"),
        ),
        sa.CheckConstraint(
            "object_confidence BETWEEN 0 AND 1",
            name=op.f("ck_wicket_detections_object_confidence_range"),
        ),
        sa.CheckConstraint(
            "temporal_stability BETWEEN 0 AND 1",
            name=op.f("ck_wicket_detections_temporal_stability_range"),
        ),
        sa.ForeignKeyConstraint(
            ["match_id"],
            ["matches.id"],
            name=op.f("fk_wicket_detections_match_id_matches"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["scene_scan_id"],
            ["scene_scans.id"],
            name=op.f("fk_wicket_detections_scene_scan_id_scene_scans"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_wicket_detections")),
    )
    op.create_index(
        "ix_wicket_detections_match_id_is_active",
        "wicket_detections",
        ["match_id", "is_active"],
        unique=False,
    )
    op.create_table(
        "deliveries",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("innings_id", sa.Uuid(), nullable=False),
        sa.Column("wicket_detection_id", sa.Uuid(), nullable=True),
        sa.Column("delivery_sequence", sa.Integer(), nullable=False),
        sa.Column("over_number", sa.SmallInteger(), nullable=False),
        sa.Column("legal_ball_number", sa.SmallInteger(), nullable=True),
        sa.Column("bowler_id", sa.Uuid(), nullable=False),
        sa.Column("striker_id", sa.Uuid(), nullable=False),
        sa.Column("non_striker_id", sa.Uuid(), nullable=True),
        sa.Column("dismissed_player_id", sa.Uuid(), nullable=True),
        sa.Column("runs_bat", sa.SmallInteger(), nullable=False),
        sa.Column("runs_extras", sa.SmallInteger(), nullable=False),
        sa.Column("is_wide", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("is_no_ball", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("is_bye", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("is_leg_bye", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("is_wicket", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("dismissal_type", sa.String(length=20), nullable=True),
        sa.Column("speed_kmph", sa.Numeric(precision=6, scale=2, asdecimal=False), nullable=True),
        sa.Column(
            "speed_confidence", sa.Numeric(precision=4, scale=3, asdecimal=False), nullable=True
        ),
        sa.Column(
            "ball_tracking_confidence",
            sa.Numeric(precision=4, scale=3, asdecimal=False),
            nullable=True,
        ),
        sa.Column(
            "pose_tracking_confidence",
            sa.Numeric(precision=4, scale=3, asdecimal=False),
            nullable=True,
        ),
        sa.Column(
            "wicket_tracking_confidence",
            sa.Numeric(precision=4, scale=3, asdecimal=False),
            nullable=True,
        ),
        sa.Column("is_voided", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("voided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("void_reason", sa.String(length=100), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "dismissal_type IS NULL OR dismissal_type IN ('BOWLED','CAUGHT','LBW','RUN_OUT','STUMPED','HIT_WICKET')",
            name=op.f("ck_deliveries_dismissal_type_valid"),
        ),
        sa.CheckConstraint(
            "ball_tracking_confidence IS NULL OR (ball_tracking_confidence BETWEEN 0 AND 1)",
            name=op.f("ck_deliveries_ball_tracking_confidence_range"),
        ),
        sa.CheckConstraint(
            "legal_ball_number IS NULL OR (legal_ball_number BETWEEN 1 AND 6)",
            name=op.f("ck_deliveries_legal_ball_number_range"),
        ),
        sa.CheckConstraint(
            "pose_tracking_confidence IS NULL OR (pose_tracking_confidence BETWEEN 0 AND 1)",
            name=op.f("ck_deliveries_pose_tracking_confidence_range"),
        ),
        sa.CheckConstraint("runs_bat BETWEEN 0 AND 7", name=op.f("ck_deliveries_runs_bat_range")),
        sa.CheckConstraint(
            "runs_extras BETWEEN 0 AND 10", name=op.f("ck_deliveries_runs_extras_range")
        ),
        sa.CheckConstraint(
            "speed_confidence IS NULL OR (speed_confidence BETWEEN 0 AND 1)",
            name=op.f("ck_deliveries_speed_confidence_range"),
        ),
        sa.CheckConstraint(
            "wicket_tracking_confidence IS NULL OR (wicket_tracking_confidence BETWEEN 0 AND 1)",
            name=op.f("ck_deliveries_wicket_tracking_confidence_range"),
        ),
        sa.ForeignKeyConstraint(
            ["bowler_id"], ["players.id"], name=op.f("fk_deliveries_bowler_id_players")
        ),
        sa.ForeignKeyConstraint(
            ["dismissed_player_id"],
            ["players.id"],
            name=op.f("fk_deliveries_dismissed_player_id_players"),
        ),
        sa.ForeignKeyConstraint(
            ["innings_id"],
            ["innings.id"],
            name=op.f("fk_deliveries_innings_id_innings"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["non_striker_id"], ["players.id"], name=op.f("fk_deliveries_non_striker_id_players")
        ),
        sa.ForeignKeyConstraint(
            ["striker_id"], ["players.id"], name=op.f("fk_deliveries_striker_id_players")
        ),
        sa.ForeignKeyConstraint(
            ["wicket_detection_id"],
            ["wicket_detections.id"],
            name=op.f("fk_deliveries_wicket_detection_id_wicket_detections"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_deliveries")),
        sa.UniqueConstraint(
            "innings_id",
            "delivery_sequence",
            name=op.f("uq_deliveries_innings_id_delivery_sequence"),
        ),
    )
    op.create_index(
        "ix_deliveries_innings_id_over_number_delivery_sequence",
        "deliveries",
        ["innings_id", "over_number", "delivery_sequence"],
        unique=False,
    )
    op.create_table(
        "delivery_decisions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("delivery_id", sa.Uuid(), nullable=False),
        sa.Column("decision_type", sa.String(length=30), nullable=False),
        sa.Column("automated_result", sa.String(length=40), nullable=True),
        sa.Column("final_result", sa.String(length=40), nullable=True),
        sa.Column("confidence", sa.Numeric(precision=4, scale=3, asdecimal=False), nullable=True),
        sa.Column(
            "decision_status",
            sa.String(length=30),
            server_default="REVIEW_RECOMMENDED",
            nullable=False,
        ),
        sa.Column(
            "decision_source", sa.String(length=30), server_default="AI_ASSIST", nullable=False
        ),
        sa.Column("evidence", JSON_DOCUMENT, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "decision_source IN ('AI_ASSIST','MANUAL')",
            name=op.f("ck_delivery_decisions_decision_source_valid"),
        ),
        sa.CheckConstraint(
            "decision_status IN ('AUTO_CALL','REVIEW_RECOMMENDED','INCONCLUSIVE','MANUAL_OVERRIDE')",
            name=op.f("ck_delivery_decisions_decision_status_valid"),
        ),
        sa.CheckConstraint(
            "decision_type IN ('WIDE','NO_BALL_HEIGHT','NO_BALL_FRONT_FOOT','EDGE','LBW','WICKET_HIT')",
            name=op.f("ck_delivery_decisions_decision_type_valid"),
        ),
        sa.CheckConstraint(
            "confidence IS NULL OR (confidence BETWEEN 0 AND 1)",
            name=op.f("ck_delivery_decisions_confidence_range"),
        ),
        sa.ForeignKeyConstraint(
            ["delivery_id"],
            ["deliveries.id"],
            name=op.f("fk_delivery_decisions_delivery_id_deliveries"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_delivery_decisions")),
    )
    op.create_index(
        "ix_delivery_decisions_delivery_id", "delivery_decisions", ["delivery_id"], unique=False
    )
    op.create_table(
        "trajectory_snapshots",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("delivery_id", sa.Uuid(), nullable=False),
        sa.Column("sampling_fps", sa.SmallInteger(), nullable=False),
        sa.Column("points_compressed", JSON_DOCUMENT, nullable=False),
        sa.Column("model_version", sa.String(length=100), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "sampling_fps BETWEEN 1 AND 240",
            name=op.f("ck_trajectory_snapshots_sampling_fps_range"),
        ),
        sa.ForeignKeyConstraint(
            ["delivery_id"],
            ["deliveries.id"],
            name=op.f("fk_trajectory_snapshots_delivery_id_deliveries"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_trajectory_snapshots")),
    )
    op.create_index(
        "ix_trajectory_snapshots_delivery_id", "trajectory_snapshots", ["delivery_id"], unique=False
    )


def downgrade() -> None:
    op.drop_index("ix_trajectory_snapshots_delivery_id", table_name="trajectory_snapshots")
    op.drop_table("trajectory_snapshots")
    op.drop_index("ix_delivery_decisions_delivery_id", table_name="delivery_decisions")
    op.drop_table("delivery_decisions")
    op.drop_index("ix_deliveries_innings_id_over_number_delivery_sequence", table_name="deliveries")
    op.drop_table("deliveries")
    op.drop_index("ix_wicket_detections_match_id_is_active", table_name="wicket_detections")
    op.drop_table("wicket_detections")
    op.drop_table("tosses")
    op.drop_index("ix_scene_scans_match_id", table_name="scene_scans")
    op.drop_table("scene_scans")
    op.drop_table("match_rules")
    op.drop_index("ix_match_players_player_id", table_name="match_players")
    op.drop_table("match_players")
    op.drop_table("innings")
    op.drop_index("ix_matches_status", table_name="matches")
    op.drop_index("ix_matches_owner_id_created_at", table_name="matches")
    op.drop_table("matches")
    op.drop_index("ix_teams_owner_id", table_name="teams")
    op.drop_table("teams")
    op.drop_table("sync_events")
    op.drop_index("ix_refresh_tokens_user_id", table_name="refresh_tokens")
    op.drop_index("ix_refresh_tokens_family_id", table_name="refresh_tokens")
    op.drop_table("refresh_tokens")
    op.drop_index("ix_players_owner_id", table_name="players")
    op.drop_table("players")
    op.drop_table("users")
