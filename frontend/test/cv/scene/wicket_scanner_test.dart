import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/adapters/mock/mock.dart';
import 'package:gully_umpire/cv/contracts/detected_object.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/cv/scene/wicket_scanner.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

/// Scans [frames] frames of the mock scene, ten frames per second.
WicketScanResult scanScenario(MockScenario scenario, {int frames = 12}) {
  final MockSceneObjectDetector detector = MockSceneObjectDetector(scenario);
  final WicketScanner scanner = WicketScanner();
  for (int i = 0; i < frames; i++) {
    final List<DetectedObject> detections = detector.detectAt(i * 100);
    BoundingBox? batsman;
    for (final DetectedObject detection in detections) {
      if (SceneLabels.isPerson(detection.label)) {
        batsman = detection.boundingBox;
      }
    }
    scanner.addFrame(detections, batsmanBox: batsman);
  }
  return scanner.result();
}

DetectedObject object(String label, double confidence, BoundingBox box) =>
    DetectedObject(label: label, confidence: confidence, boundingBox: box);

void main() {
  group('scoreWicketCandidate', () {
    test('weights add up to one', () {
      expect(
        scoreWicketCandidate(
          objectConfidence: 1,
          temporalStability: 1,
          batsmanRelationshipScore: 1,
          pitchAlignmentScore: 1,
          physicalTargetQuality: 1,
        ),
        closeTo(1, 1e-12),
      );
    });

    test('each part has its own weight', () {
      double only({
        double objectConfidence = 0,
        double temporalStability = 0,
        double batsmanRelationshipScore = 0,
        double pitchAlignmentScore = 0,
        double physicalTargetQuality = 0,
      }) =>
          scoreWicketCandidate(
            objectConfidence: objectConfidence,
            temporalStability: temporalStability,
            batsmanRelationshipScore: batsmanRelationshipScore,
            pitchAlignmentScore: pitchAlignmentScore,
            physicalTargetQuality: physicalTargetQuality,
          );
      expect(only(objectConfidence: 1), closeTo(0.30, 1e-12));
      expect(only(temporalStability: 1), closeTo(0.25, 1e-12));
      expect(only(batsmanRelationshipScore: 1), closeTo(0.20, 1e-12));
      expect(only(pitchAlignmentScore: 1), closeTo(0.15, 1e-12));
      expect(only(physicalTargetQuality: 1), closeTo(0.10, 1e-12));
    });

    test('out-of-range inputs are clamped', () {
      expect(
        scoreWicketCandidate(
          objectConfidence: 3,
          temporalStability: -1,
          batsmanRelationshipScore: 1,
          pitchAlignmentScore: 1,
          physicalTargetQuality: 1,
        ),
        closeTo(0.30 + 0.20 + 0.15 + 0.10, 1e-12),
      );
    });
  });

  group('buildWicketCandidates', () {
    test('three nearby stumps become one candidate', () {
      final List<WicketCandidate> candidates = buildWicketCandidates(<DetectedObject>[
        object('traditional_stumps', 0.9, BoundingBox.fromCenter(centerX: 0.483, centerY: 0.49, width: 0.012, height: 0.14)),
        object('traditional_stumps', 0.9, BoundingBox.fromCenter(centerX: 0.5, centerY: 0.49, width: 0.012, height: 0.14)),
        object('traditional_stumps', 0.9, BoundingBox.fromCenter(centerX: 0.517, centerY: 0.49, width: 0.012, height: 0.14)),
      ]);
      expect(candidates, hasLength(1));
      expect(candidates.single.family, WicketFamily.traditionalStumps);
      expect(candidates.single.memberCount, 3);
      expect(candidates.single.polygon.isValid, isTrue);
      expect(candidates.single.objectConfidence, closeTo(0.9, 1e-12));
    });

    test('people, weak detections and unknown labels are ignored', () {
      final List<WicketCandidate> candidates = buildWicketCandidates(<DetectedObject>[
        object('person', 0.9, BoundingBox.fromLTRB(0.4, 0.3, 0.5, 0.7)),
        object('bucket', 0.1, BoundingBox.fromLTRB(0.4, 0.4, 0.5, 0.5)),
        object('sofa', 0.9, BoundingBox.fromLTRB(0.4, 0.4, 0.5, 0.5)),
        object('cricket_ball', 0.9, BoundingBox.fromLTRB(0.4, 0.4, 0.42, 0.42)),
      ]);
      expect(candidates, isEmpty);
    });

    test('far apart bottles are separate candidates', () {
      final List<WicketCandidate> candidates = buildWicketCandidates(<DetectedObject>[
        object('bottle', 0.8, BoundingBox.fromLTRB(0.1, 0.4, 0.12, 0.5)),
        object('bottle', 0.8, BoundingBox.fromLTRB(0.8, 0.4, 0.82, 0.5)),
      ]);
      expect(candidates, hasLength(2));
    });

    test('single objects such as a chair are never merged', () {
      final List<WicketCandidate> candidates = buildWicketCandidates(<DetectedObject>[
        object('chair', 0.8, BoundingBox.fromLTRB(0.4, 0.4, 0.5, 0.6)),
        object('chair', 0.8, BoundingBox.fromLTRB(0.41, 0.4, 0.51, 0.6)),
      ]);
      expect(candidates, hasLength(2));
    });
  });

  group('WicketScanner with a clear mock scene', () {
    const Map<MockWicketKind, WicketFamily> families = <MockWicketKind, WicketFamily>{
      MockWicketKind.stumps: WicketFamily.traditionalStumps,
      MockWicketKind.chair: WicketFamily.chair,
      MockWicketKind.bricks: WicketFamily.brickStack,
      MockWicketKind.bottles: WicketFamily.bottleStack,
      MockWicketKind.cones: WicketFamily.coneStack,
      MockWicketKind.bucket: WicketFamily.bucket,
      MockWicketKind.wallTarget: WicketFamily.wallTarget,
    };

    families.forEach((MockWicketKind kind, WicketFamily family) {
      test('finds $kind in the right place', () {
        for (int seed = 1; seed <= 3; seed++) {
          final MockScenario scenario = MockScenario(seed: seed, wicketKind: kind);
          final WicketScanResult result = scanScenario(scenario);
          expect(result.foundWicket, isTrue, reason: 'seed $seed');
          expect(result.best!.family, family, reason: 'seed $seed');
          expect(result.readiness, ScanReadiness.ready, reason: 'seed $seed');
          expect(result.confidence, greaterThanOrEqualTo(0.85), reason: 'seed $seed');
          final BoundingBox truth = MockWorld(scenario).truthWicketPolygon()!.bounds;
          expect(result.best!.box.iou(truth), greaterThan(0.6), reason: 'seed $seed');
          expect(result.best!.polygon.containsPoint(truth.center), isTrue, reason: 'seed $seed');
        }
      });
    });

    test('is not fooled by the chair at the side of the picture', () {
      for (int seed = 1; seed <= 3; seed++) {
        final WicketScanResult result = scanScenario(MockScenario(seed: seed));
        expect(result.best!.family, WicketFamily.traditionalStumps);
        expect(result.alternatives, isEmpty);
      }
    });

    test('reports the batter', () {
      final WicketScanResult result = scanScenario(const MockScenario());
      expect(result.batsmanBox, isNotNull);
      expect(result.batsmanBox!.centerX, closeTo(0.5, 0.02));
      expect(result.batsmanBox!.height, closeTo(0.32, 0.001));
      expect(result.framesScanned, 12);
    });

    test('finds nothing when there is no wicket', () {
      for (int seed = 1; seed <= 3; seed++) {
        final WicketScanResult result =
            scanScenario(MockScenario(seed: seed, wicketKind: MockWicketKind.none));
        expect(result.foundWicket, isFalse);
        expect(result.best, isNull);
        expect(result.confidence, 0);
        expect(result.readiness, ScanReadiness.reposition);
      }
    });
  });

  group('WicketScanner with a poor mock scene', () {
    test('a noisy scene is found with moderate confidence', () {
      for (int seed = 1; seed <= 3; seed++) {
        final WicketScanResult result = scanScenario(
          MockScenario(seed: seed, scanQuality: MockScanQuality.moderate),
          frames: 30,
        );
        expect(result.foundWicket, isTrue, reason: 'seed $seed');
        expect(result.best!.family, WicketFamily.traditionalStumps, reason: 'seed $seed');
        expect(result.readiness, ScanReadiness.moderate, reason: 'seed $seed');
      }
    });

    test('a mostly missed scene finds no wicket', () {
      for (int seed = 1; seed <= 3; seed++) {
        final WicketScanResult result = scanScenario(
          MockScenario(seed: seed, scanQuality: MockScanQuality.low),
          frames: 30,
        );
        expect(result.foundWicket, isFalse, reason: 'seed $seed');
        expect(result.readiness, ScanReadiness.reposition, reason: 'seed $seed');
      }
    });
  });

  group('WicketScanner state', () {
    test('reset forgets all frames', () {
      final WicketScanner scanner = WicketScanner();
      final MockSceneObjectDetector detector = MockSceneObjectDetector(const MockScenario());
      for (int i = 0; i < 12; i++) {
        scanner.addFrame(detector.detectAt(i * 100));
      }
      expect(scanner.result().foundWicket, isTrue);
      scanner.reset();
      expect(scanner.framesScanned, 0);
      expect(scanner.result().foundWicket, isFalse);
    });

    test('a candidate needs enough frames before it counts', () {
      final WicketScanner scanner = WicketScanner();
      final MockSceneObjectDetector detector = MockSceneObjectDetector(const MockScenario());
      for (int i = 0; i < 3; i++) {
        scanner.addFrame(detector.detectAt(i * 100));
      }
      expect(scanner.result().foundWicket, isFalse);
    });
  });
}
