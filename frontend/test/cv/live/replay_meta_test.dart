import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/plane.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/live/replay_meta.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

import '../../support/replay_fixtures.dart';

/// Writes [meta] to JSON text and reads it back, as the replay file does.
ReplayMeta throughJsonText(ReplayMeta meta) {
  final Object? decoded = jsonDecode(jsonEncode(meta.toJson()));
  return ReplayMeta.fromJson(decoded! as Map<String, Object?>);
}

ReplayMeta fullMeta() {
  final ReplayMeta base = makeMeta(
    arrivalMs: 80,
    bounceMs: 40,
    bounced: true,
    ballHeightM: 0.8,
    ballLateralM: -0.125,
    heightUncertaintyM: 0.3,
    speedKmph: 112.5,
    waistRatio: 0.5,
    shoulderRatio: 0.8,
    notes: const <String>['Camera was behind the bowler.', 'Ball looked white.'],
  );
  return ReplayMeta(
    ballKind: base.ballKind,
    aspectRatio: base.aspectRatio,
    batterHeightM: base.batterHeightM,
    track: base.track,
    poses: <PoseSample>[poseAt(0), poseAt(40, centerX: 0.52)],
    verdicts: base.verdicts,
    wicket: base.wicket,
    plane: const ReferencePlane(
      centerX: 0.5,
      groundY: 0.9,
      metersPerUnitX: 1.5,
      metersPerUnitY: 2.75,
    ),
    arrivalMs: base.arrivalMs,
    bounceMs: base.bounceMs,
    bounced: base.bounced,
    contactMs: 640,
    ballHeightM: base.ballHeightM,
    ballLateralM: base.ballLateralM,
    heightUncertaintyM: base.heightUncertaintyM,
    speedKmph: base.speedKmph,
    trackQuality: 0.875,
    waistRatio: base.waistRatio,
    shoulderRatio: base.shoulderRatio,
    notes: base.notes,
  );
}

void main() {
  group('ReplayMeta JSON', () {
    test('keeps everything through a trip via JSON text', () {
      final ReplayMeta meta = fullMeta();

      expect(throughJsonText(meta), meta);
    });

    test('keeps a bare description with nothing optional', () {
      final ReplayMeta meta = makeMeta();

      final Map<String, Object?> json = meta.toJson();

      expect(json.containsKey('arrival_ms'), isFalse);
      expect(json.containsKey('bounce_ms'), isFalse);
      expect(json.containsKey('bounced'), isFalse);
      expect(json.containsKey('contact_ms'), isFalse);
      expect(json.containsKey('ball_height_m'), isFalse);
      expect(json.containsKey('plane'), isFalse);
      expect(throughJsonText(meta), meta);
    });

    test('the document says which layout it has', () {
      expect(makeMeta().toJson()['version'], ReplayMeta.formatVersion);
    });

    test('refuses a document of another version', () {
      final Map<String, Object?> json = makeMeta().toJson();

      expect(() => ReplayMeta.fromJson(<String, Object?>{...json, 'version': 2}), throwsFormatException);
      expect(() => ReplayMeta.fromJson(<String, Object?>{...json, 'version': '1'}), throwsFormatException);
      expect(() => ReplayMeta.fromJson(<String, Object?>{...json}..remove('version')), throwsFormatException);
    });

    test('refuses a document that lacks something it needs', () {
      final Map<String, Object?> json = makeMeta().toJson();

      for (final String key in <String>['ball_kind', 'aspect_ratio', 'batter_height_m', 'track', 'poses', 'verdicts']) {
        expect(
          () => ReplayMeta.fromJson(<String, Object?>{...json}..remove(key)),
          throwsFormatException,
          reason: 'without $key',
        );
      }
    });

    test('refuses rows that are too short', () {
      final Map<String, Object?> json = makeMeta().toJson();

      expect(
        () => ReplayMeta.fromJson(<String, Object?>{
          ...json,
          'track': <Object?>[
            <Object?>[0, 0.5, 0.5],
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => ReplayMeta.fromJson(<String, Object?>{
          ...json,
          'poses': <Object?>[
            <Object?>[0, 0.5],
          ],
        }),
        throwsFormatException,
      );
    });

    test('keeps the time of the path change, and an older replay simply has none', () {
      final ReplayMeta changed = makeMeta(contactMs: 640);

      expect(changed.toJson()['contact_ms'], 640);
      expect(throughJsonText(changed).contactMs, 640);
      expect(ReplayMeta.fromJson(makeMeta().toJson()).contactMs, isNull);
    });

    test('falls back to defaults for what an older writer left out', () {
      final Map<String, Object?> json = <String, Object?>{...makeMeta().toJson()}
        ..remove('track_quality')
        ..remove('waist_ratio')
        ..remove('shoulder_ratio')
        ..remove('notes');

      final ReplayMeta meta = ReplayMeta.fromJson(json);

      expect(meta.trackQuality, 0);
      expect(meta.waistRatio, 0.55);
      expect(meta.shoulderRatio, 0.82);
      expect(meta.notes, isEmpty);
    });

    test('drops optional values that are not usable instead of failing', () {
      final Map<String, Object?> json = <String, Object?>{
        ...makeMeta().toJson(),
        'ball_height_m': double.nan,
        'speed_kmph': double.infinity,
        'bounced': 'yes',
        'arrival_ms': 'soon',
        'notes': <Object?>[1, 'kept', null],
      };

      final ReplayMeta meta = ReplayMeta.fromJson(json);

      expect(meta.ballHeightM, isNull);
      expect(meta.speedKmph, isNull);
      expect(meta.bounced, isNull);
      expect(meta.arrivalMs, isNull);
      expect(meta.notes, <String>['kept']);
    });

    test('takes whole numbers where decimals are expected', () {
      final Map<String, Object?> json = <String, Object?>{
        ...makeMeta().toJson(),
        'aspect_ratio': 1,
        'track': <Object?>[
          <Object?>[0, 1, 0, 1, 1],
        ],
      };

      final ReplayMeta meta = ReplayMeta.fromJson(json);

      expect(meta.aspectRatio, 1.0);
      expect(meta.track.single.x, 1.0);
      expect(meta.track.single.diameter, 1.0);
    });
  });

  group('ReplayMeta details', () {
    test('knows the first and last time of the ball track', () {
      expect(makeMeta().trackSpan, (start: 0, end: 80));
      expect(makeMeta(track: const <ReplayBallPoint>[]).trackSpan, isNull);
    });

    test('a verdict falls back to its type when the label and the summary are missing', () {
      final ReplayVerdict verdict = ReplayVerdict.fromJson(const <String, Object?>{
        'type': 'WIDE',
        'result': 'NOT_WIDE',
        'status': 'AUTO',
        'confidence': 0.5,
      });

      expect(verdict.label, 'WIDE');
      expect(verdict.summary, '');
      expect(verdict.toJson()['label'], 'WIDE');
    });

    test('a verdict needs its type, result and status', () {
      for (final String key in <String>['type', 'result', 'status', 'confidence']) {
        final Map<String, Object?> json = <String, Object?>{
          'type': 'WIDE',
          'result': 'NOT_WIDE',
          'status': 'AUTO',
          'confidence': 0.5,
        }..remove(key);

        expect(() => ReplayVerdict.fromJson(json), throwsFormatException, reason: 'without $key');
      }
    });

    test('a ball point converts to and from its list form', () {
      const ReplayBallPoint point =
          ReplayBallPoint(timestampMs: 120, x: 0.25, y: 0.75, diameter: 0.03125, confidence: 0.875);

      expect(ReplayBallPoint.fromList(point.toList()), point);
      expect(() => ReplayBallPoint.fromList(<Object?>[1, 2, 3, 4]), throwsFormatException);
    });
  });

  group('ReplayMeta inside a replay file', () {
    test('comes back out of the pack that carries it', () {
      final ReplayMeta meta = fullMeta();
      final List<LumaFrame> film = <LumaFrame>[
        for (int i = 0; i < 4; i++)
          LumaFrame(width: 16, height: 9, timestampMs: i * 33, pixels: Uint8List(16 * 9)),
      ];
      final Uint8List pack = ReplayCodec.attachMeta(ReplayCodec.encode(film), meta.toJson());

      final ReplayReader reader = ReplayReader.parse(pack);

      expect(reader.frameCount, 4);
      expect(ReplayMeta.fromJson(reader.meta!), meta);
    });
  });
}
