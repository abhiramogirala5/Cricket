import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';

import '../../support/model_fixtures.dart';

/// Pushes [json] through real JSON text, like the local database and the API do.
Map<String, Object?> viaJsonText(Map<String, Object?> json) {
  final Object? decoded = jsonDecode(jsonEncode(json));
  return (decoded! as Map<Object?, Object?>).cast<String, Object?>();
}

void main() {
  group('toJson -> JSON text -> fromJson gives back an equal model', () {
    test('Team', () {
      expect(Team.fromJson(viaJsonText(sampleTeamA.toJson())), sampleTeamA);
    });

    test('Player', () {
      expect(Player.fromJson(viaJsonText(samplePlayer.toJson())), samplePlayer);
    });

    test('CricketMatch', () {
      expect(CricketMatch.fromJson(viaJsonText(sampleMatch.toJson())), sampleMatch);
    });

    test('MatchPlayer', () {
      expect(MatchPlayer.fromJson(viaJsonText(sampleMatchPlayer.toJson())), sampleMatchPlayer);
    });

    test('MatchRules', () {
      expect(MatchRules.fromJson(viaJsonText(sampleRules.toJson())), sampleRules);
    });

    test('Toss', () {
      expect(Toss.fromJson(viaJsonText(sampleToss.toJson())), sampleToss);
    });

    test('Innings (with server totals)', () {
      expect(Innings.fromJson(viaJsonText(sampleInnings.toJson())), sampleInnings);
    });

    test('Delivery (with derived and void fields)', () {
      expect(Delivery.fromJson(viaJsonText(sampleDelivery.toJson())), sampleDelivery);
    });

    test('DecisionRecord', () {
      expect(DecisionRecord.fromJson(viaJsonText(sampleDecision.toJson())), sampleDecision);
    });

    test('SceneScan', () {
      expect(SceneScan.fromJson(viaJsonText(sampleScan.toJson())), sampleScan);
    });

    test('WicketDetection', () {
      expect(WicketDetection.fromJson(viaJsonText(sampleWicket.toJson())), sampleWicket);
    });

    test('TrajectorySnapshot', () {
      expect(TrajectorySnapshot.fromJson(viaJsonText(sampleTrajectory.toJson())), sampleTrajectory);
    });
  });

  group('parsing server responses', () {
    test('a read shape with extra unknown fields is accepted', () {
      final Map<String, Object?> json = viaJsonText(sampleTeamA.toJson())..['future_field'] = 1;
      expect(Team.fromJson(json), sampleTeamA);
    });

    test('timestamps with fractional seconds and offsets are normalised to UTC', () {
      final Map<String, Object?> json = viaJsonText(sampleTeamA.toJson())
        ..['created_at'] = '2026-10-08T13:03:00.500+05:30';
      expect(Team.fromJson(json).createdAt, DateTime.utc(2026, 10, 8, 7, 33, 0, 500));
    });

    test('a missing required field is a FormatException', () {
      final Map<String, Object?> json = viaJsonText(sampleTeamA.toJson())..remove('name');
      expect(() => Team.fromJson(json), throwsFormatException);
    });

    test('an unknown enum value is a FormatException (never silently coerced)', () {
      final Map<String, Object?> json = viaJsonText(sampleMatch.toJson())..['status'] = 'PAUSED';
      expect(() => CricketMatch.fromJson(json), throwsFormatException);
    });

    test('an unknown batting hand falls back to unknown', () {
      final Map<String, Object?> json = viaJsonText(samplePlayer.toJson())..['batting_hand'] = 'BOTH';
      expect(Player.fromJson(json).battingHand, BattingHand.unknown);
    });

    test('numeric strings from a sloppy source still parse', () {
      final Map<String, Object?> json = viaJsonText(sampleInnings.toJson())..['total_runs'] = '41';
      expect(Innings.fromJson(json).totalRuns, 41);
    });
  });
}
