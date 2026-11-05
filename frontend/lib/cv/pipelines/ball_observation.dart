import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';

/// One accepted ball detection: where it was, how sure the detector was, and how big it looked.
///
/// The apparent size is what lets a single camera tell how far away the ball is: the diameter
/// shrinks as the ball flies away from the camera towards the batter.
final class BallObservation extends Equatable {
  const BallObservation({
    required this.timestampMs,
    required this.x,
    required this.y,
    required this.confidence,
    required this.diameter,
  });

  final int timestampMs;

  /// Normalised image position of the middle of the ball.
  final double x;
  final double y;

  final double confidence;

  /// Apparent ball diameter as a fraction of the picture height.
  final double diameter;

  Point2D get position => Point2D(x, y);

  BallTrackPoint toTrackPoint() =>
      BallTrackPoint(timestampMs: timestampMs, x: x, y: y, confidence: confidence);

  @override
  List<Object?> get props => <Object?>[timestampMs, x, y, confidence, diameter];
}
