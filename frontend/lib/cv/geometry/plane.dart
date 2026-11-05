import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/point3d.dart';

/// A vertical reference plane (for example the plane the batsman stands in),
/// expressed as a pair of linear scales between normalised image coordinates
/// and metres.
///
/// The scale is derived from a subject of known height standing on the plane
/// (the batsman). It is a pinhole approximation: it is only accurate for points
/// that really are on the plane. A ball that is nearer to or further from the
/// camera than the plane is mis-measured; this is the single-camera depth
/// ambiguity the product warns about, and why the confidence of every result
/// that uses a plane is capped.
final class ReferencePlane extends Equatable {
  const ReferencePlane({
    required this.centerX,
    required this.groundY,
    required this.metersPerUnitX,
    required this.metersPerUnitY,
  });

  /// Builds the plane from a subject standing on it.
  ///
  /// [centerX], [groundY] and [topY] are the subject's normalised centre,
  /// feet and top of head. [subjectHeightM] is its real height.
  /// [aspectRatio] is frame width divided by frame height, because one
  /// normalised unit spans more pixels horizontally than vertically.
  factory ReferencePlane.fromSubject({
    required double centerX,
    required double groundY,
    required double topY,
    required double subjectHeightM,
    required double aspectRatio,
  }) {
    final double heightNorm = groundY - topY;
    if (!(heightNorm > 1e-6) || !(subjectHeightM > 0) || !(aspectRatio > 0)) {
      throw ArgumentError('A reference plane needs a positive subject height and aspect ratio');
    }
    final double perY = subjectHeightM / heightNorm;
    return ReferencePlane(
      centerX: centerX,
      groundY: groundY,
      metersPerUnitX: perY * aspectRatio,
      metersPerUnitY: perY,
    );
  }

  /// Normalised x of the plane origin (lateral offset 0).
  final double centerX;

  /// Normalised y of the ground on the plane (height 0).
  final double groundY;

  /// Metres per normalised horizontal unit.
  final double metersPerUnitX;

  /// Metres per normalised vertical unit.
  final double metersPerUnitY;

  /// Signed lateral offset in metres of image x [x] from the plane origin
  /// (positive to the image right).
  double lateralMeters(double x) => (x - centerX) * metersPerUnitX;

  /// Height above the ground in metres of image y [y].
  double heightMeters(double y) => (groundY - y) * metersPerUnitY;

  /// The image point as metres on the plane (`z` is 0).
  Point3D toWorld(Point2D p) => Point3D(lateralMeters(p.x), heightMeters(p.y), 0);

  /// Image x for a lateral offset of [meters].
  double xForLateralMeters(double meters) => centerX + meters / metersPerUnitX;

  /// Image y for a height of [meters] above the ground.
  double yForHeightMeters(double meters) => groundY - meters / metersPerUnitY;

  /// A copy with a different origin (for example when the batsman has moved).
  ReferencePlane withCenterX(double newCenterX) => ReferencePlane(
        centerX: newCenterX,
        groundY: groundY,
        metersPerUnitX: metersPerUnitX,
        metersPerUnitY: metersPerUnitY,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'center_x': centerX,
        'ground_y': groundY,
        'meters_per_unit_x': metersPerUnitX,
        'meters_per_unit_y': metersPerUnitY,
      };

  @override
  List<Object?> get props => <Object?>[centerX, groundY, metersPerUnitX, metersPerUnitY];

  @override
  String toString() =>
      'ReferencePlane(centerX: ${centerX.toStringAsFixed(3)}, groundY: ${groundY.toStringAsFixed(3)}, '
      'mx: ${metersPerUnitX.toStringAsFixed(3)}, my: ${metersPerUnitY.toStringAsFixed(3)})';
}
