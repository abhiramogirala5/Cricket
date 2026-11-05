import 'package:equatable/equatable.dart';

/// A point in metres on a reference plane (spec §6 `Point3D`).
///
/// Convention used by the rules: [x] is the lateral offset (positive to the
/// image right), [y] is the height above the ground and [z] is the distance
/// along the pitch from the reference plane (0 on the plane itself).
final class Point3D extends Equatable {
  const Point3D(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  @override
  List<Object?> get props => <Object?>[x, y, z];

  @override
  String toString() => 'Point3D(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}
