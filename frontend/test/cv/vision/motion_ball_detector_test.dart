import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/vision/background_model.dart';
import 'package:gully_umpire/cv/vision/blob_finder.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';
import 'package:gully_umpire/cv/vision/motion_ball_detector.dart';

const int width = 160;
const int height = 90;

/// A grey picture with round discs (centre in pixels, radius, brightness).
LumaFrame scene({
  List<({int x, int y, int r, int value})> discs = const <({int x, int y, int r, int value})>[],
  int base = 100,
  int t = 0,
}) {
  final Uint8List pixels = Uint8List(width * height)..fillRange(0, width * height, base);
  for (final ({int x, int y, int r, int value}) disc in discs) {
    for (int y = disc.y - disc.r; y <= disc.y + disc.r; y++) {
      for (int x = disc.x - disc.r; x <= disc.x + disc.r; x++) {
        final int dx = x - disc.x;
        final int dy = y - disc.y;
        if (dx * dx + dy * dy <= disc.r * disc.r) {
          pixels[y * width + x] = disc.value;
        }
      }
    }
  }
  return LumaFrame(width: width, height: height, timestampMs: t, pixels: pixels);
}

/// A detector that has seen the empty scene for four pictures.
MotionBallDetector learnedDetector() {
  final MotionBallDetector detector = MotionBallDetector();
  for (int i = 0; i < 4; i++) {
    detector.process(scene(t: i * 33));
  }
  return detector;
}

Blob goodBlob({double cx = 80, double cy = 45}) => Blob(
      area: 29,
      cx: cx,
      cy: cy,
      major: 6.2,
      minor: 6.2,
      meanDiff: 120,
      peakDiff: 120,
      p90Diff: 120,
      halfArea: 29,
      left: cx.toInt() - 3,
      top: cy.toInt() - 3,
      right: cx.toInt() + 3,
      bottom: cy.toInt() + 3,
    );

void main() {
  group('MotionBallDetector', () {
    test('learns the scene first and reports nothing meanwhile', () {
      final MotionBallDetector detector = MotionBallDetector();

      final MotionDetection first = detector.process(scene(t: 0));
      final MotionDetection second = detector.process(scene(t: 33));
      final MotionDetection third = detector.process(scene(t: 66));

      expect(first.state, BackgroundState.warmup);
      expect(first.candidates, isEmpty);
      expect(second.state, BackgroundState.warmup);
      expect(third.state, BackgroundState.ok);
      expect(third.candidates, isEmpty);
      expect(third.blobCount, 0);
    });

    test('finds a small bright disc and places it in the picture', () {
      final MotionBallDetector detector = learnedDetector();

      final MotionDetection result = detector.process(
        scene(discs: const <({int x, int y, int r, int value})>[(x: 80, y: 45, r: 3, value: 220)], t: 200),
      );

      expect(result.state, BackgroundState.ok);
      expect(result.candidates, hasLength(1));
      final BallObservation ball = result.candidates.single;
      expect(ball.timestampMs, 200);
      // The middle of pixel (80, 45) is at 80.5, 45.5 of 160 x 90.
      expect(ball.x, closeTo(80.5 / width, 0.005));
      expect(ball.y, closeTo(45.5 / height, 0.005));
      // A disc of radius 3 covers 29 pixels: about 6 pixels across, which is 6 / 90 of the height.
      expect(ball.diameter, inInclusiveRange(0.05, 0.085));
      expect(ball.confidence, greaterThan(0.7));
      expect(result.blobCount, 1);
    });

    test('also finds a dark disc on a bright background', () {
      final MotionBallDetector detector = MotionBallDetector();
      for (int i = 0; i < 4; i++) {
        detector.process(scene(base: 200, t: i * 33));
      }

      final MotionDetection result = detector.process(
        scene(
          base: 200,
          discs: const <({int x, int y, int r, int value})>[(x: 40, y: 20, r: 3, value: 60)],
          t: 200,
        ),
      );

      expect(result.candidates, hasLength(1));
      expect(result.candidates.single.x, closeTo(40.5 / width, 0.005));
    });

    test('follows a disc that moves from picture to picture', () {
      final MotionBallDetector detector = learnedDetector();
      final List<double> xs = <double>[];

      for (int i = 0; i < 5; i++) {
        final MotionDetection result = detector.process(
          scene(
            discs: <({int x, int y, int r, int value})>[(x: 30 + i * 20, y: 40, r: 3, value: 220)],
            t: 200 + i * 33,
          ),
        );
        expect(result.candidates, isNotEmpty, reason: 'picture $i');
        xs.add(result.candidates.first.x);
      }

      for (int i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]));
        expect(xs[i] - xs[i - 1], closeTo(20 / width, 0.01));
      }
    });

    test('two discs give two candidates, the more ball-like first', () {
      final MotionBallDetector detector = learnedDetector();

      final MotionDetection result = detector.process(
        scene(
          discs: const <({int x, int y, int r, int value})>[
            (x: 40, y: 30, r: 3, value: 220),
            (x: 120, y: 60, r: 2, value: 220),
          ],
          t: 200,
        ),
      );

      expect(result.candidates, hasLength(2));
      expect(result.candidates[0].confidence, greaterThanOrEqualTo(result.candidates[1].confidence));
    });

    test('a person-sized moving block is not a ball but is seen as movement', () {
      final MotionBallDetector detector = learnedDetector();
      final Uint8List pixels = Uint8List(width * height)..fillRange(0, width * height, 100);
      for (int y = 10; y < 70; y++) {
        for (int x = 60; x < 100; x++) {
          pixels[y * width + x] = 220;
        }
      }

      final MotionDetection result = detector.process(
        LumaFrame(width: width, height: height, timestampMs: 200, pixels: pixels),
      );

      expect(result.candidates, isEmpty);
      expect(result.foregroundFraction, closeTo(2400 / (width * height), 1e-9));
    });

    test('a dim disc that barely differs from the background is not trusted', () {
      final MotionBallDetector detector = learnedDetector();

      final MotionDetection result = detector.process(
        scene(discs: const <({int x, int y, int r, int value})>[(x: 80, y: 45, r: 3, value: 108)], t: 200),
      );

      expect(result.candidates, isEmpty);
    });

    test('reset makes it learn the scene again', () {
      final MotionBallDetector detector = learnedDetector();

      detector.reset();

      expect(detector.process(scene(t: 500)).state, BackgroundState.warmup);
    });
  });

  group('scoreBlobs', () {
    List<BallObservation> score(List<Blob> blobs, {MotionDetectorConfig? config}) => scoreBlobs(
          blobs,
          threshold: 12,
          width: width,
          height: height,
          timestampMs: 77,
          config: config ?? const MotionDetectorConfig(),
        );

    test('a compact, solid, contrasting patch is a confident candidate', () {
      final List<BallObservation> result = score(<Blob>[goodBlob()]);

      expect(result, hasLength(1));
      expect(result.single.confidence, greaterThan(0.8));
      expect(result.single.x, closeTo(0.5, 1e-12));
      expect(result.single.y, closeTo(0.5, 1e-12));
      expect(result.single.timestampMs, 77);
    });

    test('a single speck is dropped', () {
      const Blob speck = Blob(
        area: 1,
        cx: 20.5,
        cy: 20.5,
        major: 1.15,
        minor: 1.15,
        meanDiff: 200,
        peakDiff: 200,
        p90Diff: 200,
        halfArea: 1,
        left: 20,
        top: 20,
        right: 20,
        bottom: 20,
      );

      expect(score(<Blob>[speck]), isEmpty);
    });

    test('a patch larger than 12 percent of the picture height is dropped', () {
      const Blob huge = Blob(
        area: 400,
        cx: 80,
        cy: 45,
        major: 22.6,
        minor: 22.6,
        meanDiff: 120,
        peakDiff: 120,
        p90Diff: 120,
        halfArea: 400,
        left: 69,
        top: 34,
        right: 91,
        bottom: 56,
      );

      expect(score(<Blob>[huge]), isEmpty);
    });

    test('a long smear is dropped', () {
      const Blob smear = Blob(
        area: 30,
        cx: 80,
        cy: 45,
        major: 36,
        minor: 3,
        meanDiff: 120,
        peakDiff: 120,
        p90Diff: 120,
        halfArea: 30,
        left: 62,
        top: 44,
        right: 98,
        bottom: 46,
      );

      expect(score(<Blob>[smear]), isEmpty);
    });

    test('a ring (mostly empty inside) is less convincing than a solid disc', () {
      const Blob ring = Blob(
        area: 14,
        cx: 80,
        cy: 45,
        major: 6.2,
        minor: 6.2,
        meanDiff: 120,
        peakDiff: 120,
        p90Diff: 120,
        halfArea: 14,
        left: 77,
        top: 42,
        right: 83,
        bottom: 48,
      );

      final List<BallObservation> solid = score(<Blob>[goodBlob()]);
      final List<BallObservation> hollow = score(<Blob>[ring]);

      expect(hollow.isEmpty || hollow.single.confidence < solid.single.confidence, isTrue);
    });

    test('a weak contrast lowers the confidence', () {
      const Blob faint = Blob(
        area: 29,
        cx: 80,
        cy: 45,
        major: 6.2,
        minor: 6.2,
        meanDiff: 15,
        peakDiff: 20,
        p90Diff: 18,
        halfArea: 29,
        left: 77,
        top: 42,
        right: 83,
        bottom: 48,
      );

      final List<BallObservation> bright = score(<Blob>[goodBlob()]);
      final List<BallObservation> weak = score(<Blob>[faint]);

      expect(weak.isEmpty || weak.single.confidence < bright.single.confidence, isTrue);
    });

    test('at most maxCandidates are returned, best first', () {
      final List<Blob> blobs = <Blob>[
        for (int i = 0; i < 10; i++) goodBlob(cx: 10.0 + i * 12, cy: 45),
      ];

      final List<BallObservation> result = score(blobs);

      expect(result, hasLength(6));
      for (int i = 1; i < result.length; i++) {
        expect(result[i - 1].confidence, greaterThanOrEqualTo(result[i].confidence));
      }
      expect(
        score(blobs, config: const MotionDetectorConfig(maxCandidates: 3)),
        hasLength(3),
      );
    });

    test('no blobs, no candidates', () {
      expect(score(const <Blob>[]), isEmpty);
    });
  });

  group('MotionDetectorConfig', () {
    test('configs with the same values are equal', () {
      expect(const MotionDetectorConfig(), const MotionDetectorConfig());
      expect(const MotionDetectorConfig(), isNot(const MotionDetectorConfig(maxCandidates: 2)));
    });
  });
}
