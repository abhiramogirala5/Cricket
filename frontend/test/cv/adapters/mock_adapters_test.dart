import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/adapters/mock/mock.dart';
import 'package:gully_umpire/cv/contracts/audio_impulse.dart';
import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/contracts/detected_object.dart';
import 'package:gully_umpire/cv/contracts/pose.dart';

const MockScenario base = MockScenario();

/// Metres per normalised vertical unit for the default batsman (1.70 m between y 0.34 and 0.66).
const double metersPerUnitY = 1.70 / (0.66 - 0.34);

/// Image diameter of the 7 cm ball when it is on the batsman plane.
const double planeDiameter = 0.07 / metersPerUnitY;

double heightToY(double meters) => 0.66 - meters / metersPerUnitY;

void main() {
  group('MockCamera', () {
    test('produces evenly spaced frames including both ends', () {
      final List<CameraFrameInput> frames = MockCamera.frameList(fps: 30, startMs: 0, endMs: 1000);
      expect(frames, hasLength(31));
      expect(frames.first.timestampMs, 0);
      expect(frames.last.timestampMs, 1000);
      expect(frames[3].timestampMs, 100);
      expect(frames.first.width, 1280);
      expect(frames.first.height, 720);
    });

    test('rounds timestamps to whole milliseconds at 60 fps', () {
      final List<int> times = MockCamera.frameList(fps: 60, startMs: 0, endMs: 100)
          .map<int>((CameraFrameInput f) => f.timestampMs)
          .toList();
      expect(times, <int>[0, 17, 33, 50, 67, 83, 100]);
    });

    test('an invalid range gives no frames', () {
      expect(MockCamera.frameList(fps: 0, startMs: 0, endMs: 1000), isEmpty);
      expect(MockCamera.frameList(fps: 30, startMs: 500, endMs: 100), isEmpty);
    });

    test('the stream carries the same frames as the list', () async {
      final List<CameraFrameInput> fromStream =
          await MockCamera.frames(fps: 30, startMs: 100, endMs: 400).toList();
      final List<CameraFrameInput> fromList = MockCamera.frameList(fps: 30, startMs: 100, endMs: 400);
      expect(
        fromStream.map<int>((CameraFrameInput f) => f.timestampMs).toList(),
        fromList.map<int>((CameraFrameInput f) => f.timestampMs).toList(),
      );
    });
  });

  group('every adapter is labelled as a mock', () {
    test('model versions start with mock-', () {
      expect(MockSceneObjectDetector(base).modelInfo.version, startsWith(CvModelInfo.mockPrefix));
      expect(MockBallDetector(base).modelInfo.isMock, isTrue);
      expect(MockPoseEstimator(base).modelInfo.isMock, isTrue);
      expect(MockAudioAnalyzer(base).modelInfo.isMock, isTrue);
    });
  });

  group('MockWorld ball motion (default straight hit, release at 2000 ms)', () {
    const MockWorld world = MockWorld(base);

    test('there is no ball before the release or after the delivery', () {
      expect(world.ballAt(1999), isNull);
      expect(world.ballAt(3101), isNull);
      expect(world.ballAt(2000), isNotNull);
      expect(world.ballAt(3100), isNotNull);
    });

    test('the ball starts small and high up the image', () {
      final MockBallState state = world.ballAt(2000)!;
      expect(state.x, closeTo(0.50, 1e-9));
      expect(state.y, closeTo(0.19, 1e-9));
      // 3 m from the camera plane distance 18 m: six times the plane diameter.
      expect(state.diameter, closeTo(planeDiameter * 6, 1e-9));
    });

    test('the ball bounces low in the image and grows as it comes closer', () {
      final MockBallState state = world.ballAt(2540)!;
      expect(state.x, closeTo(0.505, 1e-9));
      expect(state.y, closeTo(0.75, 1e-9));
      expect(state.diameter, closeTo(planeDiameter * 1.5, 1e-9));
    });

    test('at the batsman plane the ball has exactly the plane diameter', () {
      final MockBallState state = world.ballAt(2900)!;
      expect(state.x, closeTo(0.51, 1e-9));
      expect(state.y, closeTo(heightToY(0.74), 1e-9));
      expect(state.diameter, closeTo(planeDiameter, 1e-9));
    });

    test('the batsman plane is reached 900 ms after the release', () {
      expect(MockWorld.arrivalMs, 900);
      expect(world.contactMs, 2900);
    });

    test('only bat and pad deliveries have a contact', () {
      for (final MockDeliveryKind kind in MockDeliveryKind.values) {
        final MockWorld w = MockWorld(base.copyWith(deliveryKind: kind));
        final bool expected = kind == MockDeliveryKind.lbwHitting ||
            kind == MockDeliveryKind.lbwMissing ||
            kind == MockDeliveryKind.edge;
        expect(w.hasContact, expected, reason: kind.name);
      }
    });

    test('the batsman only moves when a shift is set, between 300 and 900 ms', () {
      expect(world.batsmanCenterXAt(2900), 0.5);
      final MockWorld shifting = MockWorld(base.copyWith(batsmanShiftX: 0.12));
      expect(shifting.batsmanCenterXAt(2000), 0.5);
      expect(shifting.batsmanCenterXAt(2300), 0.5);
      expect(shifting.batsmanCenterXAt(2600), closeTo(0.56, 1e-9));
      expect(shifting.batsmanCenterXAt(2900), closeTo(0.62, 1e-9));
      expect(shifting.batsmanCenterXAt(5000), closeTo(0.62, 1e-9));
    });

    test('the truth polygon exists unless there is no wicket', () {
      expect(world.truthWicketPolygon(), isNotNull);
      expect(MockWorld(base.copyWith(wicketKind: MockWicketKind.none)).truthWicketPolygon(), isNull);
    });
  });

  group('MockBallDetector', () {
    test('the same timestamp always gives the same detections', () {
      final MockBallDetector a = MockBallDetector(base);
      final MockBallDetector b = MockBallDetector(base);
      for (int ts = 2000; ts <= 3100; ts += 37) {
        expect(a.detectAt(ts), b.detectAt(ts), reason: 'ts=$ts');
        expect(a.detectAt(ts), a.detectAt(ts), reason: 'ts=$ts again');
      }
    });

    test('different seeds give different noise', () {
      final MockBallDetector a = MockBallDetector(base);
      final MockBallDetector b = MockBallDetector(base.copyWith(seed: 2));
      int differing = 0;
      for (int ts = 2000; ts <= 3100; ts += 50) {
        if (a.detectAt(ts).toString() != b.detectAt(ts).toString()) {
          differing += 1;
        }
      }
      expect(differing, greaterThan(10));
    });

    test('with no dropout the true ball is found near its true position', () {
      final MockScenario scenario = base.copyWith(ballDropout: 0);
      final MockBallDetector detector = MockBallDetector(scenario);
      const MockWorld world = MockWorld(base);
      for (int ts = 2000; ts <= 3100; ts += 50) {
        final MockBallState truth = world.ballAt(ts)!;
        final List<DetectedObject> found = detector.detectAt(ts);
        final Iterable<DetectedObject> near = found.where(
          (DetectedObject o) =>
              o.confidence >= 0.5 &&
              (o.boundingBox.centerX - truth.x).abs() < 0.02 &&
              (o.boundingBox.centerY - truth.y).abs() < 0.02,
        );
        expect(near, isNotEmpty, reason: 'ts=$ts');
        expect(near.first.label, SceneLabels.ball);
      }
    });

    test('there is nothing real to find outside the delivery', () {
      final MockBallDetector detector = MockBallDetector(base.copyWith(ballDropout: 0));
      for (int ts = 0; ts < 2000; ts += 50) {
        // Only the weak distractor can appear (confidence below 0.65).
        for (final DetectedObject o in detector.detectAt(ts)) {
          expect(o.confidence, lessThan(0.66), reason: 'ts=$ts');
        }
      }
    });

    test('the lost-ball scenario drops most detections', () {
      final MockBallDetector detector = MockBallDetector(
        base.copyWith(deliveryKind: MockDeliveryKind.lostBall),
      );
      int strong = 0;
      for (int ts = 2000; ts <= 3100; ts += 25) {
        strong += detector.detectAt(ts).where((DetectedObject o) => o.confidence >= 0.8).length;
      }
      // 45 samples, about 70% dropped.
      expect(strong, lessThan(25));
    });
  });

  group('MockPoseEstimator', () {
    test('returns all 33 landmarks with the head above the feet', () {
      final PoseResult? pose = MockPoseEstimator(base).estimateAt(2000);
      expect(pose, isNotNull);
      expect(pose!.landmarks, hasLength(PoseLandmarkIndex.count));
      expect(pose.confidence, greaterThan(0.8));
      final PoseLandmark nose = pose.landmark(PoseLandmarkIndex.nose)!;
      final PoseLandmark foot = pose.landmark(PoseLandmarkIndex.leftFootIndex)!;
      final PoseLandmark hip = pose.landmark(PoseLandmarkIndex.leftHip)!;
      expect(nose.y, lessThan(hip.y));
      expect(hip.y, lessThan(foot.y));
      // The nose sits at 92% of the standing height above the ground.
      expect(foot.y, closeTo(0.66, 0.02));
      expect(nose.y, closeTo(0.66 - 0.92 * 0.32, 0.02));
      expect(nose.x, closeTo(0.5, 0.02));
    });

    test('the person is reported as visible', () {
      final PoseResult pose = MockPoseEstimator(base).estimateAt(2000)!;
      expect(pose.landmark(PoseLandmarkIndex.nose)!.visibility, closeTo(0.95, 1e-9));
    });

    test('no pose is available when the quality is none', () {
      final MockPoseEstimator estimator =
          MockPoseEstimator(base.copyWith(poseQuality: MockPoseQuality.none));
      expect(estimator.estimateAt(2000), isNull);
    });

    test('is deterministic', () {
      final MockPoseEstimator a = MockPoseEstimator(base);
      final MockPoseEstimator b = MockPoseEstimator(base);
      expect(a.estimateAt(2123), b.estimateAt(2123));
    });

    test('follows a batsman who moves sideways', () {
      final MockPoseEstimator estimator =
          MockPoseEstimator(base.copyWith(batsmanShiftX: 0.12));
      final double early = estimator.estimateAt(2000)!.landmark(PoseLandmarkIndex.nose)!.x;
      final double late = estimator.estimateAt(2900)!.landmark(PoseLandmarkIndex.nose)!.x;
      expect(late - early, closeTo(0.12, 0.02));
    });
  });

  group('MockAudioAnalyzer', () {
    test('hears only a quiet background sound for a normal delivery', () async {
      final MockAudioAnalyzer analyzer = MockAudioAnalyzer(base);
      final List<AudioImpulse> impulses = await analyzer.getRecentImpulses(0, 10000);
      expect(impulses, hasLength(1));
      expect(impulses.single.timestampMs, 2300);
      expect(impulses.single.impulseConfidence, lessThan(0.5));
    });

    test('an edge adds a bright click exactly at the contact', () async {
      final MockAudioAnalyzer analyzer = MockAudioAnalyzer(base.copyWith(deliveryKind: MockDeliveryKind.edge));
      final List<AudioImpulse> impulses = await analyzer.getRecentImpulses(0, 10000);
      expect(impulses, hasLength(2));
      final AudioImpulse click = impulses.last;
      expect(click.timestampMs, 2900);
      expect(click.spectralCentroid, 3200);
      expect(click.peakAmplitude, 0.6);
      expect(click.impulseConfidence, 0.9);
    });

    test('only impulses inside the requested window are returned', () async {
      final MockAudioAnalyzer analyzer = MockAudioAnalyzer(base.copyWith(deliveryKind: MockDeliveryKind.edge));
      expect((await analyzer.getRecentImpulses(2850, 2950)).single.timestampMs, 2900);
      expect(await analyzer.getRecentImpulses(0, 2000), isEmpty);
    });
  });
}
