import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/scene_scan_pipeline.dart';
import 'package:gully_umpire/cv/scene/wicket_scanner.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

/// Version string stored with a wicket that the umpire marked by hand.
const String manualMarkModelVersion = 'manual-mark-1';

/// The wicket must cover at least this part of the picture (0.0004 is a 2 % x 2 % square)...
const double minWicketArea = 0.0004;

/// ...and at most this part of it (a "wicket" filling most of the picture is a mistake).
const double maxWicketArea = 0.5;

/// Why a marked wicket cannot be used, or `null` when it is fine.
///
/// The four corners must be inside the picture, form a simple (not crossed) four-sided shape
/// that bends the same way at every corner, and be neither a speck nor most of the picture.
String? wicketCornersProblem(List<Point2D> corners) {
  if (corners.length != 4) {
    return 'Mark all four corners of the stumps.';
  }
  for (final Point2D corner in corners) {
    if (!corner.isFinite || corner.x < 0 || corner.x > 1 || corner.y < 0 || corner.y > 1) {
      return 'Keep every corner inside the picture.';
    }
  }
  final Polygon polygon = Polygon(corners);
  if (!polygon.isValid || polygon.area < minWicketArea) {
    return 'The marked area is too small. Drag the corners further apart.';
  }
  if (polygon.area > maxWicketArea) {
    return 'The marked area is too big. Mark only the stumps or the object you use as the wicket.';
  }
  if (!_isConvex(corners)) {
    return 'The corners cross over each other. Go around the stumps in order.';
  }
  return null;
}

/// True when every corner turns the same way (so the shape is simple and has no dent).
bool _isConvex(List<Point2D> corners) {
  int positive = 0;
  int negative = 0;
  final int n = corners.length;
  for (int i = 0; i < n; i++) {
    final Point2D a = corners[i];
    final Point2D b = corners[(i + 1) % n];
    final Point2D c = corners[(i + 2) % n];
    final double turn = (b - a).cross(c - b);
    if (turn > 1e-9) {
      positive++;
    } else if (turn < -1e-9) {
      negative++;
    } else {
      return false;
    }
  }
  return positive == 0 || negative == 0;
}

/// A first guess for the stumps in the middle of the picture: a narrow, tall shape in the
/// centre (corners in the order top-left, top-right, bottom-right, bottom-left).
List<Point2D> defaultWicketCorners() => const <Point2D>[
      Point2D(0.45, 0.35),
      Point2D(0.55, 0.35),
      Point2D(0.55, 0.65),
      Point2D(0.45, 0.65),
    ];

/// Turns four corners marked by the umpire into the same outcome a scan would produce, so the
/// rest of the app (storing the wicket, the toss, the decisions) treats both the same way.
///
/// The marking is the umpire's own statement, so every score is 0.9 ("trusted, but never
/// perfect") and the model version says it was marked by hand. Throws [ArgumentError] when
/// [wicketCornersProblem] finds a problem, so callers check that first.
SceneScanOutcome manualWicketOutcome({
  required List<Point2D> corners,
  required WicketFamily family,
  BoundingBox? batsmanBox,
}) {
  final String? problem = wicketCornersProblem(corners);
  if (problem != null) {
    throw ArgumentError.value(corners, 'corners', problem);
  }
  final Polygon polygon = Polygon(corners);
  const double trusted = 0.9;
  final WicketScanCandidate candidate = WicketScanCandidate(
    family: family,
    box: polygon.bounds,
    polygon: polygon,
    objectConfidence: trusted,
    temporalStability: trusted,
    batsmanRelationshipScore: trusted,
    pitchAlignmentScore: trusted,
    physicalTargetQuality: trusted,
    finalConfidence: trusted,
    seenFrames: 1,
  );
  return SceneScanOutcome(
    result: WicketScanResult(
      best: candidate,
      alternatives: const <WicketScanCandidate>[],
      framesScanned: 1,
      batsmanBox: batsmanBox,
    ),
    framesScanned: 1,
    modelVersion: manualMarkModelVersion,
    isMock: false,
  );
}
