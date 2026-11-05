import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/tracking/ball_tracker.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// Tuning of the [MultiBallTracker].
final class MultiTrackerConfig extends Equatable {
  const MultiTrackerConfig({
    this.maxHypotheses = 10,
    this.gate = 13.8,
    this.maxSizeRatio = 2.2,
    this.sizeWindowMs = 400,
    this.minSegmentPoints = 3,
    this.looseSpeed = 6.0,
    this.minAdoptPoints = 4,
    this.maxFinished = 16,
    this.clutterColumns = 160,
    this.clutterRows = 90,
    this.clutterMinMs = 400,
    this.clutterMaxIdleMs = 500,
  });

  /// Most candidate paths followed at the same time.
  final int maxHypotheses;

  /// Mahalanobis gate (chi-square, two degrees of freedom) for matching a detection to a path.
  final double gate;

  /// A detection whose size differs from the path's last one by more than this factor is not
  /// the same ball.
  final double maxSizeRatio;
  final int sizeWindowMs;

  /// A stretch of a path with fewer points than this is clutter.
  final int minSegmentPoints;

  /// Largest plausible picture speed of the ball (picture units per second) when an established
  /// path adopts a detection that does not fit its prediction (a bounce or a bat contact).
  final double looseSpeed;

  /// A path needs this many points before it may adopt such a detection.
  final int minAdoptPoints;

  /// Finished paths that are kept for the choice of the best one.
  final int maxFinished;

  /// Resolution of the map that remembers where things keep reappearing.
  final int clutterColumns;
  final int clutterRows;

  /// Something that stays at the same place and size for this long is stationary clutter.
  final int clutterMinMs;

  /// A clutter cell that has not been seen for this long is forgotten.
  final int clutterMaxIdleMs;

  @override
  List<Object?> get props => <Object?>[
        maxHypotheses,
        gate,
        maxSizeRatio,
        sizeWindowMs,
        minSegmentPoints,
        looseSpeed,
        minAdoptPoints,
        maxFinished,
        clutterColumns,
        clutterRows,
        clutterMinMs,
        clutterMaxIdleMs,
      ];
}

/// One candidate ball path: a Kalman-filtered track plus the detections it accepted.
final class BallHypothesis {
  BallHypothesis._(this.id, this._config, int gapMs, BallObservation first)
      : _tracker = BallTracker(config: BallTrackerConfig(maxGapMs: gapMs), capacity: 8),
        firstTimestampMs = first.timestampMs,
        lastTimestampMs = first.timestampMs {
    offer(first);
  }

  /// Order of creation (used to break ties the same way every time).
  final int id;

  final MultiTrackerConfig _config;
  final BallTracker _tracker;
  final List<BallObservation> _records = <BallObservation>[];
  int _segmentStart = 0;
  BallObservation? _lastRejected;

  /// Time of the first detection this path ever saw.
  final int firstTimestampMs;

  /// Time of the latest accepted detection.
  int lastTimestampMs;

  /// Accepted detections, oldest first, including a possibly still short last stretch.
  List<BallObservation> get records => _records;

  BallObservation? get last => _records.isEmpty ? null : _records.last;

  /// Apparent size of the latest accepted detection.
  double? get lastDiameter => _records.isEmpty ? null : _records.last.diameter;

  /// Squared Mahalanobis distance of a detection from where this path expects the ball.
  double? gateDistance(BallObservation o) =>
      _tracker.gateDistanceSquared(o.timestampMs, o.x, o.y, confidence: o.confidence);

  /// Feeds one detection. A new stretch begins whenever the filter restarts, and a previous
  /// stretch that stayed shorter than [MultiTrackerConfig.minSegmentPoints] is removed.
  BallTrackStatus offer(BallObservation o) {
    final int rejectedBefore = _tracker.rejectedCount;
    final BallTrackStatus status = _tracker.update(
      timestampMs: o.timestampMs,
      x: o.x,
      y: o.y,
      confidence: o.confidence,
    );
    switch (status) {
      case BallTrackStatus.started:
        _beginSegment();
        _records.add(o);
        lastTimestampMs = o.timestampMs;
      case BallTrackStatus.resegmented:
        _beginSegment();
        final BallObservation? pending = _lastRejected;
        if (pending != null) {
          _records.add(pending);
        }
        _records.add(o);
        lastTimestampMs = o.timestampMs;
      case BallTrackStatus.accepted:
        _records.add(o);
        lastTimestampMs = o.timestampMs;
      case BallTrackStatus.rejected:
        if (_tracker.rejectedCount > rejectedBefore) {
          _lastRejected = o;
        }
    }
    return status;
  }

  /// The accepted detections without a trailing stretch that is too short to be trusted.
  List<BallObservation> finalRecords() {
    if (_records.length - _segmentStart < _config.minSegmentPoints) {
      return List<BallObservation>.of(_records.take(math.min(_segmentStart, _records.length)));
    }
    return List<BallObservation>.of(_records);
  }

  /// How much this path looks like a thrown ball, 0..1: confident detections, enough of them,
  /// and a path that really moves or changes size.
  double quality() {
    final int n = _records.length;
    if (n < 3) {
      return 0;
    }
    double confidence = 0;
    for (final BallObservation o in _records) {
      confidence += o.confidence;
    }
    confidence /= n;
    final double points = scoreRising(n.toDouble(), low: 3, high: 10);
    double path = 0;
    for (int i = 1; i < n; i++) {
      final double dx = _records[i].x - _records[i - 1].x;
      final double dy = _records[i].y - _records[i - 1].y;
      path += math.sqrt(dx * dx + dy * dy);
    }
    final double first = _records.first.diameter;
    final double latest = _records.last.diameter;
    final double sizeChange = math.log(math.max(latest, 1e-6) / math.max(first, 1e-6)).abs();
    final double moved = math.max(
      math.min(1.0, path / 0.06),
      math.min(1.0, sizeChange / math.log(1.35)),
    );
    final double shrink = latest < first * 0.9 ? 1.0 : 0.0;
    return confidence * points * (0.3 + 0.7 * moved) * (0.8 + 0.2 * shrink);
  }

  void _beginSegment() {
    _dropShortSegment();
    _segmentStart = _records.length;
  }

  void _dropShortSegment() {
    if (_records.length - _segmentStart < _config.minSegmentPoints) {
      _records.removeRange(math.min(_segmentStart, _records.length), _records.length);
    }
  }
}

/// A cell of the stationary-clutter map.
final class _ClutterCell {
  _ClutterCell(this.firstMs, this.lastMs, this.diameter);

  final int firstMs;
  int lastMs;
  final double diameter;
}

/// Remembers where detections keep showing up at the same place and size (a swaying head, a
/// flickering leaf), so the tracker does not start a ball path from them.
///
/// The picture is divided into a coarse grid. A cell that has been hit continuously for
/// [MultiTrackerConfig.clutterMinMs] is "stationary". A ball never stays in one cell that long.
final class StationaryClutterMap {
  StationaryClutterMap(this._config);

  final MultiTrackerConfig _config;
  final Map<int, _ClutterCell> _cells = <int, _ClutterCell>{};

  int get cellCount => _cells.length;

  void clear() => _cells.clear();

  int _column(BallObservation o) {
    final int c = (o.x * _config.clutterColumns).floor();
    return c < 0 ? 0 : (c >= _config.clutterColumns ? _config.clutterColumns - 1 : c);
  }

  int _row(BallObservation o) {
    final int r = (o.y * _config.clutterRows).floor();
    return r < 0 ? 0 : (r >= _config.clutterRows ? _config.clutterRows - 1 : r);
  }

  static int _key(int column, int row) => column * 4096 + row;

  bool _sameSize(double diameter, _ClutterCell cell) {
    final double ratio = diameter / math.max(cell.diameter, 1e-9);
    return ratio >= 0.7 && ratio <= 1.4;
  }

  /// Is [o] where something has stood still for a while?
  bool isStationary(BallObservation o) {
    final int column = _column(o);
    final int row = _row(o);
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        final _ClutterCell? cell = _cells[_key(column + dx, row + dy)];
        if (cell != null &&
            cell.lastMs - cell.firstMs >= _config.clutterMinMs &&
            _sameSize(o.diameter, cell)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Records this frame's detections.
  void update(int timestampMs, List<BallObservation> detections) {
    final List<int> stale = <int>[];
    for (final MapEntry<int, _ClutterCell> entry in _cells.entries) {
      if (timestampMs - entry.value.lastMs > _config.clutterMaxIdleMs) {
        stale.add(entry.key);
      }
    }
    for (final int key in stale) {
      _cells.remove(key);
    }
    for (final BallObservation o in detections) {
      final int column = _column(o);
      final int row = _row(o);
      int? hit;
      for (int dx = -1; dx <= 1 && hit == null; dx++) {
        for (int dy = -1; dy <= 1 && hit == null; dy++) {
          final int key = _key(column + dx, row + dy);
          final _ClutterCell? cell = _cells[key];
          if (cell != null && _sameSize(o.diameter, cell)) {
            hit = key;
          }
        }
      }
      if (hit == null) {
        _cells[_key(column, row)] = _ClutterCell(timestampMs, timestampMs, o.diameter);
      } else {
        _cells[hit]!.lastMs = timestampMs;
      }
    }
  }
}

/// Follows several possible ball paths at once and chooses between them later
/// ("track before decide"), which is what makes a ball findable among swaying people.
///
/// Every frame, each detection is matched to the path that expects it (nearest in the Kalman
/// gate), established paths may adopt a detection that breaks their prediction (the ball changed
/// direction at a bounce or a bat), and detections that nobody wants start new paths, unless they
/// sit in stationary clutter. A path that has not been matched for [gapMs] is finished.
final class MultiBallTracker {
  MultiBallTracker({this.config = const MultiTrackerConfig(), this.gapMs = 100})
      : _clutter = StationaryClutterMap(config);

  final MultiTrackerConfig config;

  /// Silence after which a path is finished (set from the camera's frame interval).
  int gapMs;

  final StationaryClutterMap _clutter;
  final List<BallHypothesis> _active = <BallHypothesis>[];
  final List<BallHypothesis> _finished = <BallHypothesis>[];
  int _nextId = 0;

  /// Paths that are still being followed.
  List<BallHypothesis> get active => List<BallHypothesis>.unmodifiable(_active);

  /// Paths that ended and are still kept.
  List<BallHypothesis> get finished => List<BallHypothesis>.unmodifiable(_finished);

  int get clutterCells => _clutter.cellCount;

  /// Forgets every path (the clutter map is kept: the scene has not changed).
  void clearPaths() {
    _active.clear();
    _finished.clear();
  }

  /// Forgets everything.
  void reset() {
    clearPaths();
    _clutter.clear();
  }

  bool _sizeFits(BallHypothesis h, BallObservation c) {
    final double? lastDiameter = h.lastDiameter;
    if (lastDiameter == null || c.timestampMs - h.lastTimestampMs > config.sizeWindowMs) {
      return true;
    }
    final double ratio = c.diameter / lastDiameter;
    return !(ratio > config.maxSizeRatio || ratio < 1 / config.maxSizeRatio);
  }

  /// Processes the detections of one frame (all with the same timestamp).
  void step(int timestampMs, List<BallObservation> detections) {
    final List<bool> stationary = <bool>[
      for (final BallObservation c in detections) _clutter.isStationary(c),
    ];
    _clutter.update(timestampMs, detections);

    final Set<int> used = <int>{};
    final Set<BallHypothesis> matched = <BallHypothesis>{};

    // 1. Each detection goes to the path that expects it best.
    final List<_Pair> pairs = <_Pair>[];
    for (final BallHypothesis h in _active) {
      for (int j = 0; j < detections.length; j++) {
        final BallObservation c = detections[j];
        final double? g = h.gateDistance(c);
        if (g != null && g <= config.gate && _sizeFits(h, c)) {
          pairs.add(_Pair(g, h, j));
        }
      }
    }
    pairs.sort((_Pair a, _Pair b) {
      final int byDistance = a.gate.compareTo(b.gate);
      return byDistance != 0 ? byDistance : a.hypothesis.id.compareTo(b.hypothesis.id);
    });
    for (final _Pair pair in pairs) {
      if (matched.contains(pair.hypothesis) || used.contains(pair.index)) {
        continue;
      }
      pair.hypothesis.offer(detections[pair.index]);
      matched.add(pair.hypothesis);
      used.add(pair.index);
    }

    // 2. An established path adopts the nearest detection that fits its speed, even when it
    //    breaks the prediction: the ball changed direction (bounce, bat or pad).
    for (final BallHypothesis h in _active) {
      if (matched.contains(h) || h.records.length < config.minAdoptPoints) {
        continue;
      }
      final double dt = (timestampMs - h.lastTimestampMs) / 1000.0;
      if (dt <= 0 || dt > gapMs / 1000.0) {
        continue;
      }
      final BallObservation lastSeen = h.records.last;
      int? best;
      double bestDistance = double.infinity;
      for (int j = 0; j < detections.length; j++) {
        if (used.contains(j) || !_sizeFits(h, detections[j])) {
          continue;
        }
        final double dx = detections[j].x - lastSeen.x;
        final double dy = detections[j].y - lastSeen.y;
        final double distance = math.sqrt(dx * dx + dy * dy);
        if (distance <= config.looseSpeed * dt && distance < bestDistance) {
          bestDistance = distance;
          best = j;
        }
      }
      if (best != null) {
        h.offer(detections[best]);
        matched.add(h);
        used.add(best);
      }
    }

    // 3. Detections that nobody wants start new paths (never from stationary clutter).
    for (int j = 0; j < detections.length; j++) {
      if (used.contains(j) || stationary[j]) {
        continue;
      }
      if (_active.length >= config.maxHypotheses) {
        BallHypothesis worst = _active.first;
        double worstQuality = worst.quality();
        for (final BallHypothesis h in _active) {
          final double q = h.quality();
          if (q < worstQuality) {
            worst = h;
            worstQuality = q;
          }
        }
        if (worstQuality > 0.0 && worst.records.length > 2) {
          continue;
        }
        _active.remove(worst);
      }
      _active.add(BallHypothesis._(_nextId, config, gapMs, detections[j]));
      _nextId += 1;
    }

    // 4. Paths that were not matched for too long are finished.
    final List<BallHypothesis> keep = <BallHypothesis>[];
    for (final BallHypothesis h in _active) {
      if (timestampMs - h.lastTimestampMs > gapMs) {
        _finished.add(h);
      } else {
        keep.add(h);
      }
    }
    _active
      ..clear()
      ..addAll(keep);
    _trimFinished();

    // 5. Two paths that sit on the same detection are one path.
    _active.sort((BallHypothesis a, BallHypothesis b) {
      final int byLength = b.records.length.compareTo(a.records.length);
      return byLength != 0 ? byLength : a.id.compareTo(b.id);
    });
    final List<BallHypothesis> unique = <BallHypothesis>[];
    for (final BallHypothesis h in _active) {
      bool duplicate = false;
      final BallObservation? mine = h.last;
      for (final BallHypothesis other in unique) {
        final BallObservation? theirs = other.last;
        if (mine != null && theirs != null && mine.timestampMs == theirs.timestampMs) {
          final double dx = mine.x - theirs.x;
          final double dy = mine.y - theirs.y;
          if (math.sqrt(dx * dx + dy * dy) < 0.002) {
            duplicate = true;
            break;
          }
        }
      }
      if (!duplicate) {
        unique.add(h);
      }
    }
    _active
      ..clear()
      ..addAll(unique);
  }

  void _trimFinished() {
    while (_finished.length > config.maxFinished) {
      int worst = 0;
      double worstQuality = _finished.first.quality();
      for (int i = 1; i < _finished.length; i++) {
        final double q = _finished[i].quality();
        if (q < worstQuality) {
          worst = i;
          worstQuality = q;
        }
      }
      _finished.removeAt(worst);
    }
  }

  /// The most ball-like path among those followed and those finished, or null when none has at
  /// least [minPoints] points and a quality of at least [minQuality].
  ///
  /// When [accept] is given, only paths whose points it accepts are considered (for example paths
  /// that fly away from the camera).
  TrackedBall? best({
    int minPoints = 6,
    double minQuality = 0.25,
    bool Function(List<BallObservation> observations)? accept,
  }) {
    TrackedBall? chosen;
    for (final BallHypothesis h in <BallHypothesis>[..._active, ..._finished]) {
      final List<BallObservation> records = h.finalRecords();
      if (records.length < minPoints) {
        continue;
      }
      if (accept != null && !accept(records)) {
        continue;
      }
      final double q = h.quality();
      if (q >= minQuality && (chosen == null || q > chosen.quality)) {
        chosen = TrackedBall(quality: q, observations: records, hypothesis: h);
      }
    }
    return chosen;
  }
}

/// The path chosen by [MultiBallTracker.best].
final class TrackedBall {
  const TrackedBall({
    required this.quality,
    required this.observations,
    required this.hypothesis,
  });

  final double quality;
  final List<BallObservation> observations;
  final BallHypothesis hypothesis;
}

final class _Pair {
  const _Pair(this.gate, this.hypothesis, this.index);

  final double gate;
  final BallHypothesis hypothesis;
  final int index;
}
