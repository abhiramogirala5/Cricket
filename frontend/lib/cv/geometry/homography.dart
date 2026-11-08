import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';

/// 3x3 Homography transformation matrix mapping planar projective coordinates.
///
/// Grounded in Hartley & Zisserman (Multiple View Geometry in Computer Vision):
/// Maps 2D camera pixel coordinates (x, y) to a metric 2D ground plane (X, Y)
/// via the projective relation:
///
///   [X', Y', W']^T = H * [x, y, 1]^T
///   X = X' / W',  Y = Y' / W'
final class HomographyMatrix extends Equatable {
  const HomographyMatrix(this.elements);

  /// 9 elements in row-major order:
  /// [ h00, h01, h02,
  ///   h10, h11, h12,
  ///   h20, h21, h22 ]
  final List<double> elements;

  /// Identity homography (no change).
  static const HomographyMatrix identity = HomographyMatrix(<double>[
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    0.0, 0.0, 1.0,
  ]);

  /// Computes the 3x3 Homography matrix mapping 4 source points to 4 destination points
  /// using the Direct Linear Transformation (DLT) algorithm with Gaussian elimination.
  static HomographyMatrix? from4Points({
    required List<Point2D> src,
    required List<Point2D> dst,
  }) {
    if (src.length < 4 || dst.length < 4) {
      return null;
    }

    // Solve Ah = 0 where A is an 8x8 matrix (with h22 = 1.0)
    // For each correspondence (x, y) -> (u, v):
    //   h00*x + h01*y + h02 - u*(h20*x + h21*y + 1) = 0
    //   h10*x + h11*y + h12 - v*(h20*x + h21*y + 1) = 0
    final List<List<double>> a = List<List<double>>.generate(8, (_) => List<double>.filled(9, 0.0));

    for (int i = 0; i < 4; i++) {
      final double x = src[i].x;
      final double y = src[i].y;
      final double u = dst[i].x;
      final double v = dst[i].y;

      final int r1 = 2 * i;
      final int r2 = 2 * i + 1;

      // First equation for u
      a[r1][0] = x;
      a[r1][1] = y;
      a[r1][2] = 1.0;
      a[r1][3] = 0.0;
      a[r1][4] = 0.0;
      a[r1][5] = 0.0;
      a[r1][6] = -u * x;
      a[r1][7] = -u * y;
      a[r1][8] = u; // RHS

      // Second equation for v
      a[r2][0] = 0.0;
      a[r2][1] = 0.0;
      a[r2][2] = 0.0;
      a[r2][3] = x;
      a[r2][4] = y;
      a[r2][5] = 1.0;
      a[r2][6] = -v * x;
      a[r2][7] = -v * y;
      a[r2][8] = v; // RHS
    }

    // Solve 8x8 linear system via Gaussian elimination with partial pivoting
    for (int col = 0; col < 8; col++) {
      int pivotRow = col;
      double maxVal = a[col][col].abs();
      for (int row = col + 1; row < 8; row++) {
        final double val = a[row][col].abs();
        if (val > maxVal) {
          maxVal = val;
          pivotRow = row;
        }
      }

      if (maxVal < 1e-9) {
        return null; // Singular configuration
      }

      // Swap rows
      if (pivotRow != col) {
        final List<double> temp = a[col];
        a[col] = a[pivotRow];
        a[pivotRow] = temp;
      }

      // Eliminate column below and above
      final double pivot = a[col][col];
      for (int k = col; k < 9; k++) {
        a[col][k] /= pivot;
      }

      for (int row = 0; row < 8; row++) {
        if (row != col) {
          final double factor = a[row][col];
          if (factor.abs() > 1e-12) {
            for (int k = col; k < 9; k++) {
              a[row][k] -= factor * a[col][k];
            }
          }
        }
      }
    }

    return HomographyMatrix(<double>[
      a[0][8], a[1][8], a[2][8],
      a[3][8], a[4][8], a[5][8],
      a[6][8], a[7][8], 1.0,
    ]);
  }

  /// Projects a 2D source point through the homography matrix.
  Point2D project(Point2D p) {
    final double x = p.x;
    final double y = p.y;
    final double w = elements[6] * x + elements[7] * y + elements[8];
    if (w.abs() < 1e-9) {
      return p;
    }
    final double px = (elements[0] * x + elements[1] * y + elements[2]) / w;
    final double py = (elements[3] * x + elements[4] * y + elements[5]) / w;
    return Point2D(px, py);
  }

  @override
  List<Object?> get props => elements;
}

