import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/replay_meta.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';

/// A ball position at [t] ms.
ReplayBallPoint ballPoint(int t, {double x = 0.5, double y = 0.5, double d = 0.02, double c = 0.9}) =>
    ReplayBallPoint(timestampMs: t, x: x, y: y, diameter: d, confidence: c);

/// A batter standing at [centerX] whose feet are at [groundY] and whose head is at [topY].
PoseSample poseAt(
  int t, {
  double centerX = 0.5,
  double groundY = 0.9,
  double topY = 0.3,
  double confidence = 0.9,
}) =>
    PoseSample(
      timestampMs: t,
      centerX: centerX,
      groundY: groundY,
      topY: topY,
      confidence: confidence,
    );

/// A small replay description with a ball coming down the picture and one verdict.
ReplayMeta makeMeta({
  List<ReplayBallPoint>? track,
  List<PoseSample>? poses,
  Polygon? wicket,
  int? arrivalMs,
  int? bounceMs,
  bool? bounced,
  int? contactMs,
  double? ballHeightM,
  double? ballLateralM,
  double? heightUncertaintyM,
  double? speedKmph,
  double waistRatio = 0.55,
  double shoulderRatio = 0.82,
  List<String> notes = const <String>[],
}) {
  return ReplayMeta(
    ballKind: 'CRICKET_BALL',
    aspectRatio: 0.5625,
    batterHeightM: 1.7,
    track: track ??
        <ReplayBallPoint>[
          ballPoint(0, x: 0.50, y: 0.20, d: 0.010),
          ballPoint(40, x: 0.50, y: 0.40, d: 0.014),
          ballPoint(80, x: 0.51, y: 0.60, d: 0.020),
        ],
    poses: poses ?? <PoseSample>[poseAt(0)],
    verdicts: const <ReplayVerdict>[
      ReplayVerdict(
        typeWire: 'NO_BALL_HEIGHT',
        label: 'No ball (height)',
        result: 'NOT_NO_BALL',
        statusWire: 'REVIEW_RECOMMENDED',
        confidence: 0.7,
        summary: 'Below the waist.',
      ),
    ],
    wicket: wicket ??
        Polygon(const <Point2D>[
          Point2D(0.45, 0.35),
          Point2D(0.55, 0.35),
          Point2D(0.55, 0.65),
          Point2D(0.45, 0.65),
        ]),
    arrivalMs: arrivalMs,
    bounceMs: bounceMs,
    bounced: bounced,
    contactMs: contactMs,
    ballHeightM: ballHeightM,
    ballLateralM: ballLateralM,
    heightUncertaintyM: heightUncertaintyM,
    speedKmph: speedKmph,
    waistRatio: waistRatio,
    shoulderRatio: shoulderRatio,
    notes: notes,
  );
}
