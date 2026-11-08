import 'dart:math' as math;

import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/util/length_units.dart';
import 'package:gully_umpire/data/settings/live_settings.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

/// What was typed into the "how far is the phone from the batter" box: nothing, a usable number of
/// feet, or something that cannot be a distance (with the words to tell the person).
final class DistanceEntry {
  const DistanceEntry._(this.feet, this.problem);

  /// Nothing typed: no distance, and no problem.
  static const DistanceEntry empty = DistanceEntry._(null, null);

  const DistanceEntry.valid(double feet) : this._(feet, null);

  const DistanceEntry.invalid(String problem) : this._(null, problem);

  /// The distance in feet, or null when nothing usable was typed.
  final double? feet;

  /// Why what was typed cannot be used, or null.
  final String? problem;

  bool get isValid => problem == null;
}

/// Reads the typed text as a distance in feet.
DistanceEntry parseDistanceFeet(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return DistanceEntry.empty;
  }
  final double? value = double.tryParse(text);
  if (value == null || !value.isFinite) {
    return const DistanceEntry.invalid('Type the distance as a number of feet, like 45.');
  }
  if (value < LiveSettings.minDistanceFeet || value > LiveSettings.maxDistanceFeet) {
    return DistanceEntry.invalid(
      'Between ${LiveSettings.minDistanceFeet.round()} and ${LiveSettings.maxDistanceFeet.round()} '
      'feet, please.',
    );
  }
  return DistanceEntry.valid(value);
}

/// A saved distance as it is shown in the box: no decimals for a whole number of feet.
String distanceText(double feet) {
  return feet == feet.roundToDouble() ? feet.round().toString() : feet.toStringAsFixed(1);
}

/// Physical height in metres of a wicket of kind [family].
double typicalWicketHeightMetres(WicketFamily family) {
  return switch (family) {
    WicketFamily.traditionalStumps => 0.7112, // Standard 28 inches (ICC / MCC Law 8.1)
    WicketFamily.chair => 0.78,             // Standard plastic patio / lawn chair
    WicketFamily.bucket => 0.38,            // Standard 20L paint / utility bucket
    WicketFamily.brickStack => 0.45,        // Standard 6-brick stack (~7.5cm each)
    WicketFamily.bottleStack => 0.40,       // 2-litre beverage bottles
    WicketFamily.coneStack => 0.45,         // Standard sports training cones
    WicketFamily.bagOrObject => 0.45,       // Cricket kit bag upright
    WicketFamily.wallTarget => 0.7112,      // Chalk / paint marked wall target
    WicketFamily.unknownPhysicalObject => 0.60,
  };
}

/// Estimates the batter's upright standing height in metres from optical perspective
/// relative to the marked wicket.
///
/// Grounded in MCC Law 41.7 and perspective geometry:
/// At the striker's crease plane, the ratio of apparent heights in normalized screen units
/// matches the ratio of their real physical dimensions:
///   H_stance = (h_batter / h_wicket) * H_wicket
/// In a cricket batting stance, knee flexion and forward lean reduce apparent height
/// by ~10% (stance height ~ 0.90 * standing height).
/// MCC Law 41.7 requires no-ball assessment relative to the batsman "standing upright".
double? estimateOpticalBatsmanHeightM({
  required double batterHeightNorm,
  required Polygon wicket,
  WicketFamily family = WicketFamily.traditionalStumps,
}) {
  if (batterHeightNorm <= 0.05 || !wicket.isValid) {
    return null;
  }
  final double wicketHeightNorm = wicket.bounds.height;
  if (wicketHeightNorm <= 0.015) {
    return null;
  }
  final double realWicketHeightM = typicalWicketHeightMetres(family);
  // Apparent stance height in metres at the crease plane
  final double stanceHeightM = (batterHeightNorm / wicketHeightNorm) * realWicketHeightM;
  // Convert batting stance to standing upright height (MCC Law 41.7: upright at crease)
  const double stanceRatio = 0.90;
  final double standingHeightM = stanceHeightM / stanceRatio;

  // Plausible human cricket player heights (1.20 m for juniors up to 2.15 m for tall adults)
  if (standingHeightM < 1.20 || standingHeightM > 2.15) {
    return null;
  }
  return standingHeightM;
}

/// Estimates the distance in feet from the camera to the wicket using pinhole camera geometry.
///
/// Grounded in monocular sports vision research (MDPI Sensors 2024; Ghimire et al. 2023):
/// The apparent vertical extent of a known physical target (stumps = 28 in / 0.71 m, chair = 0.78 m)
/// under perspective projection maps directly to metric distance:
///
///   Z = (f_norm * zoom * real_height) / h_norm
double estimateDistanceFeetFromWicket(
  List<Point2D> corners, {
  double zoom = 1.0,
  WicketFamily family = WicketFamily.traditionalStumps,
}) {
  if (corners.isEmpty) {
    return 36.0;
  }
  double minY = 1.0;
  double maxY = 0.0;
  for (final Point2D p in corners) {
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  final double hNorm = math.max(0.015, maxY - minY);
  final double realHeightM = typicalWicketHeightMetres(family);

  // Typical smartphone vertical optical focal length in normalized frame coordinates (~55 deg VFOV)
  const double fNorm = 1.05;
  final double effectiveFocal = fNorm * math.max(1.0, zoom);
  final double distanceM = (effectiveFocal * realHeightM) / hNorm;
  final double feet = metresToFeet(distanceM);

  return feet.clamp(LiveSettings.minDistanceFeet, LiveSettings.maxDistanceFeet).roundToDouble();
}

/// Starter corners for the wicket polygon centered in the pitch corridor.
///
/// If [targetDistanceFeet] is provided (e.g. 66 ft for full pitch, 50 ft for medium pitch),
/// the starter dimensions (w, h) are scaled using perspective projection
/// so the marked box naturally matches the distant stumps and calculates the exact distance.
List<Point2D> smartWicketCorners({
  WicketFamily family = WicketFamily.traditionalStumps,
  double centerX = 0.50,
  double groundY = 0.65,
  double? targetDistanceFeet,
  double zoom = 1.0,
}) {
  final (double baseW, double baseH) = switch (family) {
    WicketFamily.traditionalStumps => (0.08, 0.16),
    WicketFamily.chair => (0.14, 0.18),
    WicketFamily.bucket => (0.12, 0.12),
    WicketFamily.brickStack => (0.10, 0.14),
    WicketFamily.bottleStack => (0.10, 0.12),
    WicketFamily.coneStack => (0.10, 0.14),
    WicketFamily.bagOrObject => (0.12, 0.14),
    WicketFamily.wallTarget => (0.10, 0.16),
    WicketFamily.unknownPhysicalObject => (0.10, 0.14),
  };

  final double w;
  final double h;
  if (targetDistanceFeet != null && targetDistanceFeet > 0) {
    final double distM = feetToMetres(targetDistanceFeet);
    final double realHeightM = typicalWicketHeightMetres(family);
    const double fNorm = 1.05;
    final double effectiveFocal = fNorm * math.max(1.0, zoom);
    h = ((effectiveFocal * realHeightM) / distM).clamp(0.02, 0.35);
    w = (h * (baseW / baseH)).clamp(0.015, 0.25);
  } else {
    w = baseW;
    h = baseH;
  }

  final double left = centerX - w / 2;
  final double right = centerX + w / 2;
  final double top = groundY - h;
  final double bottom = groundY;
  return <Point2D>[
    Point2D(left, top),
    Point2D(right, top),
    Point2D(right, bottom),
    Point2D(left, bottom),
  ];
}

/// Auto-detects wicket corners from live batter pose, optical observations, or pitch heuristics.
///
/// When a batter is visible at the crease ([batterGroundPoint] and [batterHeightNorm]),
/// aligns the wicket directly to the striker's stance plane and scales its apparent dimensions
/// from the known physical height of [family] relative to a human batter (~1.75 m upright, ~1.58 m in stance).
///
/// If no batter is visible, checks for optical candidates in the pitch corridor,
/// or falls back to perspective-scaled pitch defaults for [family] at [targetDistanceFeet].
List<Point2D> autoDetectWicketCorners({
  Point2D? batterGroundPoint,
  double? batterHeightNorm,
  List<BallObservation> candidates = const <BallObservation>[],
  WicketFamily family = WicketFamily.traditionalStumps,
  double? targetDistanceFeet,
  double zoom = 1.0,
}) {
  final (double baseW, double baseH) = switch (family) {
    WicketFamily.traditionalStumps => (0.08, 0.16),
    WicketFamily.chair => (0.14, 0.18),
    WicketFamily.bucket => (0.12, 0.12),
    WicketFamily.brickStack => (0.10, 0.14),
    WicketFamily.bottleStack => (0.10, 0.12),
    WicketFamily.coneStack => (0.10, 0.14),
    WicketFamily.bagOrObject => (0.12, 0.14),
    WicketFamily.wallTarget => (0.10, 0.16),
    WicketFamily.unknownPhysicalObject => (0.10, 0.14),
  };

  if (batterGroundPoint != null && batterHeightNorm != null && batterHeightNorm > 0.05) {
    final double realWicketHeightM = typicalWicketHeightMetres(family);
    // Real upright human height is ~1.75 m. Batting stance knee flexion reduces apparent height to ~1.58 m.
    const double stanceBatterHeightM = 1.58;
    final double h = ((batterHeightNorm / stanceBatterHeightM) * realWicketHeightM).clamp(0.02, 0.35);
    final double w = (h * (baseW / baseH)).clamp(0.015, 0.25);

    final double centerX = batterGroundPoint.x.clamp(0.15, 0.85);
    final double groundY = batterGroundPoint.y.clamp(0.20, 0.95);

    final double left = centerX - w / 2;
    final double right = centerX + w / 2;
    final double top = groundY - h;
    final double bottom = groundY;
    return <Point2D>[
      Point2D(left, top),
      Point2D(right, top),
      Point2D(right, bottom),
      Point2D(left, bottom),
    ];
  }

  final List<BallObservation> corridorCandidates = <BallObservation>[
    for (final BallObservation c in candidates)
      if (c.x >= 0.25 && c.x <= 0.75 && c.y >= 0.30 && c.y <= 0.85) c,
  ];

  double centerX = 0.50;
  double groundY = 0.65;

  if (corridorCandidates.isNotEmpty) {
    double sumX = 0;
    double maxY = 0;
    for (final BallObservation c in corridorCandidates) {
      sumX += c.x;
      if (c.y > maxY) {
        maxY = c.y;
      }
    }
    centerX = (sumX / corridorCandidates.length).clamp(0.30, 0.70);
    groundY = (maxY + 0.04).clamp(0.50, 0.85);
  }

  return smartWicketCorners(
    family: family,
    centerX: centerX,
    groundY: groundY,
    targetDistanceFeet: targetDistanceFeet,
    zoom: zoom,
  );
}


