import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/models.dart';

/// One accepted ball position of a delivery: where it was in the picture (0..1) at a moment.
final class PathPoint extends Equatable {
  const PathPoint({
    required this.timeMs,
    required this.x,
    required this.y,
    required this.confidence,
  });

  final double timeMs;

  /// Horizontal position, 0 (left edge of the picture) to 1 (right edge).
  final double x;

  /// Vertical position, 0 (top of the picture) to 1 (bottom).
  final double y;

  /// How sure the detector was, 0..1.
  final double confidence;

  @override
  List<Object?> get props => <Object?>[timeMs, x, y, confidence];
}

/// Reads the stored ball path (`[timestamp_ms, x, y, confidence]` per point).
///
/// A damaged point is skipped, never thrown on: the review page should still open.
List<PathPoint> parsePathPoints(List<Object?> raw) {
  final List<PathPoint> points = <PathPoint>[];
  for (final Object? item in raw) {
    if (item is! List || item.length < 3) {
      continue;
    }
    final Object? time = item[0];
    final Object? x = item[1];
    final Object? y = item[2];
    final Object? confidence = item.length > 3 ? item[3] : 1;
    if (time is! num || x is! num || y is! num) {
      continue;
    }
    final double px = x.toDouble();
    final double py = y.toDouble();
    if (!px.isFinite || !py.isFinite) {
      continue;
    }
    double c = confidence is num ? confidence.toDouble() : 1.0;
    if (!c.isFinite) {
      c = 0;
    }
    points.add(
      PathPoint(
        timeMs: time.toDouble(),
        x: px,
        y: py,
        confidence: c < 0 ? 0 : (c > 1 ? 1 : c),
      ),
    );
  }
  return points;
}

/// `snake_case` to `Snake case`.
String humanizeKey(String key) {
  final String spaced = key.replaceAll('_', ' ').trim();
  if (spaced.isEmpty) {
    return key;
  }
  return '${spaced[0].toUpperCase()}${spaced.substring(1).toLowerCase()}';
}

/// A stored result such as `NOT_WIDE` in plain words.
String friendlyResult(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Not recorded';
  }
  switch (raw) {
    case 'WIDE':
      return 'Wide';
    case 'NOT_WIDE':
      return 'Not a wide';
    case 'NO_BALL':
      return 'No-ball';
    case 'LEGAL':
      return 'Legal ball';
    case 'INCONCLUSIVE':
      return 'Not sure';
    case 'OUT':
      return 'Out';
    case 'NOT_OUT':
      return 'Not out';
    default:
      return humanizeKey(raw);
  }
}

String decisionSourceLabel(DecisionSource source) {
  switch (source) {
    case DecisionSource.aiAssist:
      return 'Assistant';
    case DecisionSource.manual:
      return 'Umpire';
  }
}

String _number(num value) {
  final double v = value.toDouble();
  if (!v.isFinite) {
    return '-';
  }
  if (v == v.roundToDouble()) {
    return v.round().toString();
  }
  return v.toStringAsFixed(2);
}

/// The simple facts of a decision's evidence (numbers, yes/no and short texts), for the
/// "Why" section. Nested values are left out: they are for analysis, not for reading.
List<({String label, String value})> evidenceLines(
  Map<String, Object?>? evidence, {
  int maxLines = 12,
}) {
  if (evidence == null) {
    return const <({String label, String value})>[];
  }
  final List<({String label, String value})> lines = <({String label, String value})>[];
  for (final MapEntry<String, Object?> entry in evidence.entries) {
    if (lines.length >= maxLines) {
      break;
    }
    final Object? value = entry.value;
    if (value is num) {
      lines.add((label: humanizeKey(entry.key), value: _number(value)));
    } else if (value is bool) {
      lines.add((label: humanizeKey(entry.key), value: value ? 'Yes' : 'No'));
    } else if (value is String && value.isNotEmpty) {
      final String shown = value.length > 60 ? '${value.substring(0, 57)}...' : value;
      lines.add((label: humanizeKey(entry.key), value: shown));
    }
  }
  return lines;
}
