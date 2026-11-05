import 'package:flutter_test/flutter_test.dart';

import '../../support/model_fixtures.dart';

/// The exact keys of each `toSyncPayload()`, copied from docs/API_CONTRACT.md §5.3.
/// The server rejects unknown fields, so an extra or misspelled key would make every event fail.
void expectKeys(Map<String, Object?> payload, Set<String> expected, String name) {
  expect(payload.keys.toSet(), expected, reason: '$name payload keys');
}

void main() {
  group('sync payloads contain exactly the contract keys', () {
    test('PLAYER', () {
      expectKeys(
        samplePlayer.toSyncPayload(),
        <String>{'id', 'display_name', 'batting_hand', 'declared_height_cm'},
        'PLAYER',
      );
    });

    test('TEAM', () {
      expectKeys(sampleTeamA.toSyncPayload(), <String>{'id', 'name'}, 'TEAM');
    });

    test('MATCH', () {
      expectKeys(
        sampleMatch.toSyncPayload(),
        <String>{
          'id',
          'team_a_id',
          'team_b_id',
          'match_name',
          'location_name',
          'scheduled_at',
          'started_at',
          'completed_at',
          'status',
          'overs_per_innings',
          'local_rules_profile',
          'winner_team_id',
          'result_summary',
        },
        'MATCH',
      );
    });

    test('MATCH_PLAYER', () {
      expectKeys(
        sampleMatchPlayer.toSyncPayload(),
        <String>{
          'match_id',
          'player_id',
          'team_id',
          'batting_hand',
          'declared_height_cm',
          'batting_order',
          'is_captain',
          'is_wicketkeeper',
        },
        'MATCH_PLAYER',
      );
    });

    test('MATCH_RULES', () {
      expectKeys(
        sampleRules.toSyncPayload(),
        <String>{
          'match_id',
          'wide_enabled',
          'no_ball_enabled',
          'front_foot_no_ball_enabled',
          'edge_review_enabled',
          'lbw_review_enabled',
          'full_toss_above_waist_is_no_ball',
          'bounced_above_shoulder_is_no_ball',
          'max_bouncers_per_over',
          'lateral_reach_multiplier',
        },
        'MATCH_RULES',
      );
    });

    test('SCENE_SCAN', () {
      expectKeys(
        sampleScan.toSyncPayload(),
        <String>{
          'id',
          'match_id',
          'camera_device_model',
          'capture_fps',
          'scan_duration_ms',
          'ground_plane',
          'pitch_direction',
          'batsman_plane',
          'overall_confidence',
          'model_version',
          'created_at',
        },
        'SCENE_SCAN',
      );
    });

    test('WICKET_DETECTION', () {
      expectKeys(
        sampleWicket.toSyncPayload(),
        <String>{
          'id',
          'match_id',
          'scene_scan_id',
          'wicket_family',
          'bounding_box',
          'target_polygon',
          'target_plane',
          'ground_contact_line',
          'object_confidence',
          'temporal_stability',
          'context_confidence',
          'final_confidence',
          'is_active',
          'model_version',
          'detected_at',
        },
        'WICKET_DETECTION',
      );
    });

    test('TOSS', () {
      expectKeys(
        sampleToss.toSyncPayload(),
        <String>{
          'id',
          'match_id',
          'called_by_player_id',
          'call_choice',
          'result',
          'winner_team_id',
          'winner_decision',
        },
        'TOSS',
      );
    });

    test('INNINGS (no server-computed totals)', () {
      expectKeys(
        sampleInnings.toSyncPayload(),
        <String>{
          'id',
          'match_id',
          'innings_number',
          'batting_team_id',
          'bowling_team_id',
          'started_at',
          'ended_at',
        },
        'INNINGS',
      );
    });

    test('DELIVERY (no server-derived fields)', () {
      expectKeys(
        sampleDelivery.toSyncPayload(),
        <String>{
          'id',
          'innings_id',
          'bowler_id',
          'striker_id',
          'non_striker_id',
          'runs_bat',
          'runs_extras',
          'is_wide',
          'is_no_ball',
          'is_bye',
          'is_leg_bye',
          'is_wicket',
          'dismissal_type',
          'dismissed_player_id',
          'wicket_detection_id',
          'speed_kmph',
          'speed_confidence',
          'ball_tracking_confidence',
          'pose_tracking_confidence',
          'wicket_tracking_confidence',
          'created_at',
        },
        'DELIVERY',
      );
    });

    test('DELIVERY VOID', () {
      expectKeys(sampleDelivery.toVoidPayload(), <String>{'id', 'void_reason'}, 'DELIVERY VOID');
    });

    test('DELIVERY_DECISION', () {
      expectKeys(
        sampleDecision.toSyncPayload(),
        <String>{
          'id',
          'delivery_id',
          'decision_type',
          'automated_result',
          'final_result',
          'confidence',
          'decision_status',
          'decision_source',
          'evidence',
          'created_at',
        },
        'DELIVERY_DECISION',
      );
    });

    test('TRAJECTORY_SNAPSHOT', () {
      expectKeys(
        sampleTrajectory.toSyncPayload(),
        <String>{'id', 'delivery_id', 'sampling_fps', 'points_compressed', 'model_version', 'created_at'},
        'TRAJECTORY_SNAPSHOT',
      );
    });
  });

  group('sync payload values', () {
    test('timestamps are RFC 3339 UTC with a Z suffix', () {
      expect(sampleMatch.toSyncPayload()['started_at'], '2026-10-08T07:45:12.000Z');
      expect(sampleMatch.toSyncPayload()['completed_at'], isNull);
    });

    test('enums use their UPPER_SNAKE_CASE wire value', () {
      expect(sampleMatch.toSyncPayload()['status'], 'LIVE');
      expect(samplePlayer.toSyncPayload()['batting_hand'], 'LEFT');
      expect(sampleDelivery.toSyncPayload()['dismissal_type'], 'RUN_OUT');
      expect(sampleDecision.toSyncPayload()['decision_type'], 'WIDE');
      expect(sampleDecision.toSyncPayload()['decision_status'], 'MANUAL_OVERRIDE');
      expect(sampleDecision.toSyncPayload()['decision_source'], 'MANUAL');
    });

    test('a void payload carries the reason', () {
      expect(sampleDelivery.toVoidPayload(), <String, Object?>{
        'id': 'delivery-1',
        'void_reason': 'Scorer mistake',
      });
    });
  });
}
