import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/util/json_read.dart';

/// One tracked ball position: normalised image coordinates at a time.
final class BallTrackPoint extends Equatable {
  const BallTrackPoint({
    required this.timestampMs,
    required this.x,
    required this.y,
    required this.confidence,
  });

  /// Parses the API `points_compressed` element `[timestamp_ms, x, y, confidence]`.
  factory BallTrackPoint.fromCompressed(List<Object?> raw) {
    if (raw.length != 4) {
      throw FormatException('A compressed ball point has 4 values but got ${raw.length}');
    }
    return BallTrackPoint(
      timestampMs: numToInt(raw[0]),
      x: numToDouble(raw[1]),
      y: numToDouble(raw[2]),
      confidence: numToDouble(raw[3]),
    );
  }

  /// Capture time in milliseconds (same clock as the camera frames).
  final int timestampMs;

  /// Normalised horizontal position (0 left .. 1 right).
  final double x;

  /// Normalised vertical position (0 top .. 1 bottom).
  final double y;

  /// Detector confidence 0..1 of the measurement behind this point.
  final double confidence;

  Point2D get position => Point2D(x, y);

  /// `[timestampMs, x, y, confidence]`, the API `points_compressed` element.
  List<num> toCompressed() => <num>[timestampMs, x, y, confidence];

  BallTrackPoint copyWith({int? timestampMs, double? x, double? y, double? confidence}) {
    return BallTrackPoint(
      timestampMs: timestampMs ?? this.timestampMs,
      x: x ?? this.x,
      y: y ?? this.y,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  List<Object?> get props => <Object?>[timestampMs, x, y, confidence];

  @override
  String toString() =>
      'BallTrackPoint(${timestampMs}ms, ${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)}, '
      '${confidence.toStringAsFixed(2)})';
}

/// Converts whole trajectories to and from the API `points_compressed` array.
abstract final class TrajectoryCodec {
  /// The API accepts at most this many points.
  static const int maxPoints = 600;

  /// Compresses [points] to `[timestamp_ms, x, y, confidence]` rows.
  ///
  /// When there are more than [limit] points they are thinned evenly, always
  /// keeping the first and the last. When [decimals] is given, x, y and the
  /// confidence are rounded to that many decimal places to save space.
  static List<List<num>> compress(
    List<BallTrackPoint> points, {
    int limit = maxPoints,
    int? decimals,
  }) {
    final List<BallTrackPoint> chosen = _thin(points, limit);
    return chosen.map<List<num>>((BallTrackPoint p) {
      if (decimals == null) {
        return p.toCompressed();
      }
      return <num>[
        p.timestampMs,
        _round(p.x, decimals),
        _round(p.y, decimals),
        _round(p.confidence, decimals),
      ];
    }).toList();
  }

  /// Parses a `points_compressed` array.
  static List<BallTrackPoint> decompress(List<Object?> raw) {
    return raw.map<BallTrackPoint>((Object? row) => BallTrackPoint.fromCompressed(asObjectList(row))).toList();
  }

  static List<BallTrackPoint> _thin(List<BallTrackPoint> points, int limit) {
    if (limit < 2 || points.length <= limit) {
      return points;
    }
    final List<BallTrackPoint> result = <BallTrackPoint>[];
    final double step = (points.length - 1) / (limit - 1);
    for (int i = 0; i < limit; i++) {
      result.add(points[(i * step).round()]);
    }
    return result;
  }

  static double _round(double value, int decimals) {
    double factor = 1;
    for (int i = 0; i < decimals; i++) {
      factor *= 10;
    }
    return (value * factor).roundToDouble() / factor;
  }
}
