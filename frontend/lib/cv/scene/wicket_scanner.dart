import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/contracts/detected_object.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/cv/scene/spatial_hash.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

/// Weighted candidate score of spec §7. Every input is clamped to 0..1.
///
/// `0.30 object + 0.25 stability + 0.20 batsman relationship + 0.15 pitch alignment +
/// 0.10 physical target quality`.
double scoreWicketCandidate({
  required double objectConfidence,
  required double temporalStability,
  required double batsmanRelationshipScore,
  required double pitchAlignmentScore,
  required double physicalTargetQuality,
}) {
  return clamp01(objectConfidence) * 0.30 +
      clamp01(temporalStability) * 0.25 +
      clamp01(batsmanRelationshipScore) * 0.20 +
      clamp01(pitchAlignmentScore) * 0.15 +
      clamp01(physicalTargetQuality) * 0.10;
}

/// Tuning of the [WicketScanner].
final class WicketScannerConfig extends Equatable {
  const WicketScannerConfig({
    this.maxTracks = 16,
    this.topCandidatesPerFrame = 8,
    this.clusterGap = 0.03,
    this.minDetectionConfidence = 0.25,
    this.minSeenFrames = 4,
    this.associationIou = 0.25,
    this.associationCenterDistance = 0.05,
    this.historyLength = 12,
    this.pitchCenterX = 0.5,
    this.maxPolygonPoints = 32,
  });

  /// Candidate tracks kept at once; the weakest are dropped.
  final int maxTracks;

  /// Only the best K candidates of a frame are tracked (spec: K <= 8).
  final int topCandidatesPerFrame;

  /// Boxes of the same stackable kind (stumps, bottles, bricks, cones) at most this far apart
  /// (edge to edge, normalised) form one wicket.
  final double clusterGap;

  /// Detections below this confidence are ignored.
  final double minDetectionConfidence;

  /// A candidate must be seen in at least this many frames before it can be selected
  /// ("require repeated stable detection").
  final int minSeenFrames;

  /// Minimum IoU to treat a detection as the same object as an existing track.
  final double associationIou;

  /// Otherwise a detection whose centre is this close to a track's centre is still the same object.
  final double associationCenterDistance;

  /// Number of recent centres and sizes used to judge stability.
  final int historyLength;

  /// Horizontal image position of the pitch line. A camera at the bowling end looks down the
  /// pitch, so the wicket is expected near the middle.
  final double pitchCenterX;

  /// The API accepts 3-32 polygon points.
  final int maxPolygonPoints;

  @override
  List<Object?> get props => <Object?>[
        maxTracks,
        topCandidatesPerFrame,
        clusterGap,
        minDetectionConfidence,
        minSeenFrames,
        associationIou,
        associationCenterDistance,
        historyLength,
        pitchCenterX,
        maxPolygonPoints,
      ];
}

/// A possible wicket in one frame: one object or one cluster of stackable objects.
final class WicketCandidate extends Equatable {
  const WicketCandidate({
    required this.family,
    required this.box,
    required this.polygon,
    required this.objectConfidence,
    required this.memberCount,
  });

  final WicketFamily family;
  final BoundingBox box;

  /// The visible physical target (the object, or the hull of a cluster).
  final Polygon polygon;

  /// Detector confidence (mean over the members of a cluster).
  final double objectConfidence;

  /// Detections merged into this candidate.
  final int memberCount;

  @override
  List<Object?> get props => <Object?>[family, box, polygon, objectConfidence, memberCount];
}

/// Turns one frame of detections into wicket candidates.
///
/// People, balls, bats and unknown labels are ignored. Detections of stackable kinds (stumps,
/// bottles, bricks, cones) that lie close together are merged with a spatial hash into one
/// candidate whose polygon is the convex hull of the members.
List<WicketCandidate> buildWicketCandidates(
  List<DetectedObject> detections, {
  double clusterGap = 0.03,
  double minConfidence = 0.25,
  int maxPolygonPoints = 32,
}) {
  final Map<String, List<DetectedObject>> byLabel = <String, List<DetectedObject>>{};
  for (final DetectedObject detection in detections) {
    if (detection.confidence < minConfidence) {
      continue;
    }
    final String label = SceneLabels.normalize(detection.label);
    if (SceneLabels.isPerson(label) || SceneLabels.familyForLabel(label) == null) {
      continue;
    }
    if (detection.boundingBox.clampedToUnit().isEmpty) {
      continue;
    }
    byLabel.putIfAbsent(label, () => <DetectedObject>[]).add(detection);
  }

  final List<WicketCandidate> candidates = <WicketCandidate>[];
  byLabel.forEach((String label, List<DetectedObject> group) {
    final WicketFamily? family = SceneLabels.familyForLabel(label);
    if (family == null) {
      return;
    }
    final List<BoundingBox> boxes = group
        .map<BoundingBox>((DetectedObject d) => d.boundingBox.clampedToUnit())
        .toList();
    if (SceneLabels.clusterable.contains(label)) {
      for (final List<int> members in clusterBoxes(boxes, maxGap: clusterGap)) {
        candidates.add(
          _candidateFromMembers(
            family,
            <BoundingBox>[for (final int i in members) boxes[i]],
            <double>[for (final int i in members) group[i].confidence],
            maxPolygonPoints,
          ),
        );
      }
    } else {
      for (int i = 0; i < group.length; i++) {
        candidates.add(
          _candidateFromMembers(
            family,
            <BoundingBox>[boxes[i]],
            <double>[group[i].confidence],
            maxPolygonPoints,
          ),
        );
      }
    }
  });
  return candidates;
}

WicketCandidate _candidateFromMembers(
  WicketFamily family,
  List<BoundingBox> boxes,
  List<double> confidences,
  int maxPolygonPoints,
) {
  BoundingBox union = boxes.first;
  for (int i = 1; i < boxes.length; i++) {
    union = union.union(boxes[i]);
  }
  Polygon polygon;
  if (boxes.length == 1) {
    polygon = Polygon.fromBox(union);
  } else {
    final List<Point2D> corners = <Point2D>[
      for (final BoundingBox box in boxes) ...box.toPolygon(),
    ];
    polygon = Polygon.convexHullOf(corners);
    if (!polygon.isValid || polygon.length > maxPolygonPoints) {
      polygon = Polygon.fromBox(union);
    }
  }
  return WicketCandidate(
    family: family,
    box: union,
    polygon: polygon,
    objectConfidence: meanOf(confidences),
    memberCount: boxes.length,
  );
}

/// A wicket candidate with every score that went into its final confidence.
final class WicketScanCandidate extends Equatable {
  const WicketScanCandidate({
    required this.family,
    required this.box,
    required this.polygon,
    required this.objectConfidence,
    required this.temporalStability,
    required this.batsmanRelationshipScore,
    required this.pitchAlignmentScore,
    required this.physicalTargetQuality,
    required this.finalConfidence,
    required this.seenFrames,
  });

  final WicketFamily family;
  final BoundingBox box;
  final Polygon polygon;
  final double objectConfidence;
  final double temporalStability;
  final double batsmanRelationshipScore;
  final double pitchAlignmentScore;
  final double physicalTargetQuality;

  /// [scoreWicketCandidate] of the five scores above.
  final double finalConfidence;

  /// Frames in which the candidate was seen.
  final int seenFrames;

  @override
  List<Object?> get props => <Object?>[
        family,
        box,
        polygon,
        objectConfidence,
        temporalStability,
        batsmanRelationshipScore,
        pitchAlignmentScore,
        physicalTargetQuality,
        finalConfidence,
        seenFrames,
      ];
}

/// Outcome of a scan.
final class WicketScanResult extends Equatable {
  const WicketScanResult({
    required this.best,
    required this.alternatives,
    required this.framesScanned,
    this.batsmanBox,
  });

  /// The selected wicket, or null when nothing was stable and plausible enough.
  final WicketScanCandidate? best;

  /// Other plausible candidates, best first (for a "not this one" retry).
  final List<WicketScanCandidate> alternatives;

  final int framesScanned;

  /// The batsman's box if the pose estimator saw one.
  final BoundingBox? batsmanBox;

  bool get foundWicket => best != null;

  /// Final confidence of [best], or 0.
  double get confidence => best?.finalConfidence ?? 0;

  ScanReadiness get readiness => ScanReadiness.fromConfidence(confidence);

  @override
  List<Object?> get props => <Object?>[best, alternatives, framesScanned, batsmanBox];
}

/// A candidate must be at least this well aligned with the middle of the picture...
const double _minPitchAlignment = 0.5;

/// ...and at least this plausible as the thing standing next to the batter.
const double _minBatsmanRelationship = 0.5;

/// Zero-touch wicket recognition (spec §7): detections from a 1-3 second scan are tracked frame
/// to frame, scored for stability and cricket context, and the best candidate is selected.
///
/// Feed every scanned frame to [addFrame] and read [result] at any time (also while the scan is
/// still running, for the live overlay). The scanner holds only small fixed-size state.
final class WicketScanner {
  WicketScanner({this.config = const WicketScannerConfig()});

  final WicketScannerConfig config;

  final List<_Track> _tracks = <_Track>[];
  int _framesScanned = 0;
  BoundingBox? _batsmanBox;

  int get framesScanned => _framesScanned;

  /// Processes the detections of one scanned frame. [batsmanBox] (from the pose estimator) is
  /// optional; without it the batsman relationship cannot be judged and scores neutral.
  void addFrame(List<DetectedObject> detections, {BoundingBox? batsmanBox}) {
    _framesScanned += 1;
    if (batsmanBox != null && !batsmanBox.isEmpty) {
      _batsmanBox = batsmanBox;
    }

    final List<WicketCandidate> candidates = buildWicketCandidates(
      detections,
      clusterGap: config.clusterGap,
      minConfidence: config.minDetectionConfidence,
      maxPolygonPoints: config.maxPolygonPoints,
    );
    candidates.sort(
      (WicketCandidate a, WicketCandidate b) => _preScore(b).compareTo(_preScore(a)),
    );
    final List<WicketCandidate> top = candidates.length > config.topCandidatesPerFrame
        ? candidates.sublist(0, config.topCandidatesPerFrame)
        : candidates;

    final Set<_Track> matched = <_Track>{};
    final List<_Track> created = <_Track>[];
    for (final WicketCandidate candidate in top) {
      _Track? best;
      double bestScore = 0;
      for (final _Track track in _tracks) {
        if (matched.contains(track) || track.family != candidate.family) {
          continue;
        }
        final double affinity = _affinity(track, candidate);
        if (affinity > bestScore) {
          bestScore = affinity;
          best = track;
        }
      }
      if (best != null) {
        matched.add(best);
        best.observe(candidate, _framesScanned);
      } else {
        created.add(_Track(candidate, _framesScanned, config.historyLength));
      }
    }
    _tracks.addAll(created);

    if (_tracks.length > config.maxTracks) {
      _tracks.sort((_Track a, _Track b) => b.seenFrames.compareTo(a.seenFrames));
      _tracks.removeRange(config.maxTracks, _tracks.length);
    }
  }

  /// Scores every track seen often enough and picks the best plausible one.
  WicketScanResult result() {
    final List<WicketScanCandidate> scored = <WicketScanCandidate>[];
    for (final _Track track in _tracks) {
      if (track.seenFrames < config.minSeenFrames) {
        continue;
      }
      final WicketScanCandidate candidate = _score(track);
      if (_isEligible(candidate)) {
        scored.add(candidate);
      }
    }
    scored.sort(
      (WicketScanCandidate a, WicketScanCandidate b) =>
          b.finalConfidence.compareTo(a.finalConfidence),
    );
    if (scored.isEmpty) {
      return WicketScanResult(
        best: null,
        alternatives: const <WicketScanCandidate>[],
        framesScanned: _framesScanned,
        batsmanBox: _batsmanBox,
      );
    }
    final int altCount = math.min(scored.length - 1, 4);
    return WicketScanResult(
      best: scored.first,
      alternatives: scored.sublist(1, 1 + altCount),
      framesScanned: _framesScanned,
      batsmanBox: _batsmanBox,
    );
  }

  /// Forgets everything (retry scan, new innings, camera moved).
  void reset() {
    _tracks.clear();
    _framesScanned = 0;
    _batsmanBox = null;
  }

  // ---- scoring -------------------------------------------------------------------------

  /// Cheap ranking used only to choose the top-K candidates of a frame.
  double _preScore(WicketCandidate candidate) {
    return candidate.objectConfidence * 0.6 +
        _batsmanRelationship(candidate.box) * 0.2 +
        _pitchAlignment(candidate.box) * 0.2;
  }

  /// How strongly a detection belongs to an existing track; 0 means "not the same object".
  double _affinity(_Track track, WicketCandidate candidate) {
    final double iou = track.box.iou(candidate.box);
    if (iou >= config.associationIou) {
      return 1 + iou;
    }
    final double distance = track.box.center.distanceTo(candidate.box.center);
    if (distance <= config.associationCenterDistance) {
      return 0.5 * (1 - distance / config.associationCenterDistance) + 1e-6;
    }
    return 0;
  }

  WicketScanCandidate _score(_Track track) {
    final double stability = _temporalStability(track);
    final double relationship = _batsmanRelationship(track.box);
    final double alignment = _pitchAlignment(track.box);
    final double quality = _physicalTargetQuality(track.box, track.polygon);
    final double objectConfidence = clamp01(track.confidenceAverage);
    return WicketScanCandidate(
      family: track.family,
      box: track.box,
      polygon: track.polygon,
      objectConfidence: objectConfidence,
      temporalStability: stability,
      batsmanRelationshipScore: relationship,
      pitchAlignmentScore: alignment,
      physicalTargetQuality: quality,
      finalConfidence: scoreWicketCandidate(
        objectConfidence: objectConfidence,
        temporalStability: stability,
        batsmanRelationshipScore: relationship,
        pitchAlignmentScore: alignment,
        physicalTargetQuality: quality,
      ),
      seenFrames: track.seenFrames,
    );
  }

  /// Presence in the scanned frames, centre jitter and size jitter.
  double _temporalStability(_Track track) {
    final double presence =
        _framesScanned <= 0 ? 0 : clamp01(track.seenFrames / _framesScanned);
    final double motion = scoreFalling(track.meanCenterDeviation, good: 0.004, bad: 0.03);
    final double size = scoreFalling(track.areaVariation, good: 0.05, bad: 0.35);
    return clamp01(presence * 0.45 + motion * 0.35 + size * 0.20);
  }

  /// The wicket stands at the batsman's end: close to the batsman sideways and with its base near
  /// the batsman's feet line. Neutral (0.5) when no batsman was seen.
  double _batsmanRelationship(BoundingBox box) {
    final BoundingBox? batsman = _batsmanBox;
    if (batsman == null) {
      return 0.5;
    }
    final double lateral = (box.centerX - batsman.centerX).abs();
    final double goodLateral = math.min(math.max(batsman.width * 0.75, 0.04), 0.30);
    final double lateralScore = scoreFalling(lateral, good: goodLateral, bad: 0.35);
    final double baseGap = (box.bottom - batsman.bottom).abs();
    final double depthScore = scoreFalling(baseGap, good: 0.12, bad: 0.45);
    return clamp01(lateralScore * 0.6 + depthScore * 0.4);
  }

  /// A camera at the bowling end sees the wicket near the middle of the frame.
  double _pitchAlignment(BoundingBox box) {
    final double offset = (box.centerX - config.pitchCenterX).abs();
    return scoreFalling(offset, good: 0.08, bad: 0.40);
  }

  /// Plausible size, fully inside the frame, a sensible shape and a sensible height compared with
  /// the batsman.
  double _physicalTargetQuality(BoundingBox box, Polygon polygon) {
    final double area = box.area;
    if (area <= 0) {
      return 0;
    }
    final double sizeScore = scoreRising(area, low: 0.0004, high: 0.003) *
        scoreFalling(area, good: 0.10, bad: 0.40);
    final BoundingBox? visible = box.intersection(BoundingBox.unit);
    final double inside = visible == null ? 0 : clamp01(visible.area / area);
    final double ratio = box.width > 0 ? box.height / box.width : 0;
    final double shape = scoreRising(ratio, low: 0.3, high: 0.8) *
        scoreFalling(ratio, good: 4.0, bad: 9.0);
    final BoundingBox? batsman = _batsmanBox;
    double relative = 1;
    if (batsman != null && batsman.height > 0) {
      final double heightRatio = box.height / batsman.height;
      relative = scoreRising(heightRatio, low: 0.08, high: 0.2) *
          scoreFalling(heightRatio, good: 0.9, bad: 1.5);
    }
    final double validity = polygon.isValid ? 1 : 0.4;
    return clamp01((sizeScore * 0.35 + inside * 0.2 + shape * 0.2 + relative * 0.25) * validity);
  }

  /// Spec §7: buckets and bags are only accepted when static and well ranked by context; a wall
  /// target must be stable.
  bool _isEligible(WicketScanCandidate candidate) {
    // A real wicket stands in the middle of the picture and next to the batter. An object far
    // off to the side (a chair at the boundary, say) must never be offered as the wicket.
    if (candidate.pitchAlignmentScore < _minPitchAlignment ||
        candidate.batsmanRelationshipScore < _minBatsmanRelationship) {
      return false;
    }
    switch (candidate.family) {
      case WicketFamily.bucket:
      case WicketFamily.bagOrObject:
        return candidate.temporalStability >= 0.8 && candidate.batsmanRelationshipScore >= 0.6;
      case WicketFamily.wallTarget:
        return candidate.temporalStability >= 0.7;
      case WicketFamily.traditionalStumps:
      case WicketFamily.chair:
      case WicketFamily.brickStack:
      case WicketFamily.bottleStack:
      case WicketFamily.coneStack:
      case WicketFamily.unknownPhysicalObject:
        return candidate.temporalStability >= 0.4;
    }
  }
}

class _Track {
  _Track(WicketCandidate first, this.lastSeenFrame, int history)
      : family = first.family,
        box = first.box,
        polygon = first.polygon,
        _centerX = Float64List(history),
        _centerY = Float64List(history),
        _area = Float64List(history),
        _history = history {
    observe(first, lastSeenFrame);
  }

  final WicketFamily family;
  BoundingBox box;
  Polygon polygon;
  int lastSeenFrame;
  int seenFrames = 0;

  final Float64List _centerX;
  final Float64List _centerY;
  final Float64List _area;
  final int _history;
  int _written = 0;
  double _confidenceSum = 0;

  void observe(WicketCandidate candidate, int frame) {
    box = candidate.box;
    polygon = candidate.polygon;
    lastSeenFrame = frame;
    seenFrames += 1;
    _confidenceSum += candidate.objectConfidence;
    final int slot = _written % _history;
    _centerX[slot] = candidate.box.centerX;
    _centerY[slot] = candidate.box.centerY;
    _area[slot] = candidate.box.area;
    _written += 1;
  }

  int get _samples => math.min(_written, _history);

  /// Mean confidence of every detection that was matched to this track.
  double get confidenceAverage => seenFrames == 0 ? 0 : _confidenceSum / seenFrames;

  /// Mean distance of the recent centres from their average centre.
  double get meanCenterDeviation {
    final int n = _samples;
    if (n < 2) {
      return 0;
    }
    double mx = 0;
    double my = 0;
    for (int i = 0; i < n; i++) {
      mx += _centerX[i];
      my += _centerY[i];
    }
    mx /= n;
    my /= n;
    double sum = 0;
    for (int i = 0; i < n; i++) {
      final double dx = _centerX[i] - mx;
      final double dy = _centerY[i] - my;
      sum += math.sqrt(dx * dx + dy * dy);
    }
    return sum / n;
  }

  /// Coefficient of variation (standard deviation / mean) of the recent box areas.
  double get areaVariation {
    final int n = _samples;
    if (n < 2) {
      return 0;
    }
    final List<double> areas = <double>[for (int i = 0; i < n; i++) _area[i]];
    final double mean = meanOf(areas);
    if (mean <= 1e-12) {
      return 1;
    }
    return stdDevOf(areas) / mean;
  }
}
