import 'dart:math' as math;
import 'dart:typed_data';

/// A connected patch of "moving" pixels with the measurements used to judge whether it is a ball.
final class Blob {
  const Blob({
    required this.area,
    required this.cx,
    required this.cy,
    required this.major,
    required this.minor,
    required this.meanDiff,
    required this.peakDiff,
    required this.p90Diff,
    required this.halfArea,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Number of moving pixels.
  final int area;

  /// Centre in pixels (the middle of the top-left pixel is 0.5, 0.5).
  final double cx;
  final double cy;

  /// Length of the long and the short axis of the best-fitting ellipse, in pixels. For a round
  /// patch both are its diameter.
  final double major;
  final double minor;

  /// Average brightness difference of the pixels from the background.
  final double meanDiff;

  /// Largest and 90th-percentile brightness difference.
  final int peakDiff;
  final int p90Diff;

  /// Pixels whose difference is at least half of [p90Diff]. For a blurred disc this is a much more
  /// stable measure of its size than the pixels above a fixed threshold.
  final int halfArea;

  /// Pixel bounds, inclusive.
  final int left;
  final int top;
  final int right;
  final int bottom;

  double get elongation => major / math.max(minor, 1e-6);

  /// Long thin streaks (the edge of a moving shadow or limb) are never a ball.
  bool get isStrip => elongation > 12 && minor < 4;
}

/// Finds the [Blob]s in a motion picture.
///
/// The picture is scanned once for horizontal runs of pixels above the threshold. Runs that touch,
/// or are at most [joinRadius] pixels apart (so a ball that the threshold has cut into pieces is
/// put back together), are merged with a union-find, and the measurements of every merged patch
/// are added up from the runs, so the cost depends on how much moves, not on the picture size.
final class BlobFinder {
  BlobFinder({
    this.joinRadius = 2,
    this.minArea = 2,
    this.maxAreaFraction = 0.0054,
    this.maxExtentFraction = 0.12,
    this.maxBlobs = 300,
    this.maxRuns = 20000,
  }) : assert(joinRadius >= 1, 'joinRadius must be at least 1'),
       _runY = Int32List(maxRuns),
       _runX0 = Int32List(maxRuns),
       _runX1 = Int32List(maxRuns),
       _parent = Int32List(maxRuns),
       _next = Int32List(maxRuns),
       _head = Int32List(maxRuns),
       _count = Int32List(maxRuns),
       _minX = Int32List(maxRuns),
       _maxX = Int32List(maxRuns),
       _minY = Int32List(maxRuns),
       _maxY = Int32List(maxRuns),
       _sx = Float64List(maxRuns),
       _sy = Float64List(maxRuns),
       _sxx = Float64List(maxRuns),
       _syy = Float64List(maxRuns),
       _sxy = Float64List(maxRuns);

  /// Pixels closer than this (in either direction) belong to the same patch. 1 means touching only.
  final int joinRadius;

  /// Patches with fewer moving pixels are noise.
  final int minArea;

  /// Patches with more than this share of the picture are not a ball.
  final double maxAreaFraction;

  /// Patches wider or taller than this share of the picture height are not a ball.
  final double maxExtentFraction;

  /// At most this many patches are measured per frame.
  final int maxBlobs;

  /// A frame with more runs than this is too noisy to use and gives no blobs.
  final int maxRuns;

  final Int32List _runY;
  final Int32List _runX0;
  final Int32List _runX1;
  final Int32List _parent;
  final Int32List _next;
  final Int32List _head;
  final Int32List _count;
  final Int32List _minX;
  final Int32List _maxX;
  final Int32List _minY;
  final Int32List _maxY;
  final Float64List _sx;
  final Float64List _sy;
  final Float64List _sxx;
  final Float64List _syy;
  final Float64List _sxy;
  final Int32List _histogram = Int32List(256);
  Int32List _rowStart = Int32List(0);

  /// Measures the moving patches of [diff] (`width * height` brightness differences).
  List<Blob> find({
    required Uint8List diff,
    required int width,
    required int height,
    required int threshold,
  }) {
    if (_rowStart.length < height + 1) {
      _rowStart = Int32List(height + 1);
    }
    final Int32List rowStart = _rowStart;

    // 1. Runs of moving pixels.
    int runs = 0;
    for (int y = 0; y < height; y++) {
      rowStart[y] = runs;
      final int rowBase = y * width;
      int x = 0;
      while (x < width) {
        if (diff[rowBase + x] > threshold) {
          final int start = x;
          x += 1;
          while (x < width && diff[rowBase + x] > threshold) {
            x += 1;
          }
          if (runs >= maxRuns) {
            return const <Blob>[];
          }
          _runY[runs] = y;
          _runX0[runs] = start;
          _runX1[runs] = x - 1;
          _parent[runs] = runs;
          runs += 1;
        } else {
          x += 1;
        }
      }
    }
    rowStart[height] = runs;
    if (runs == 0) {
      return const <Blob>[];
    }

    // 2. Merge runs that are close to each other.
    final int reach = joinRadius;
    for (int i = 0; i < runs; i++) {
      final int y = _runY[i];
      final int x0 = _runX0[i];
      final int x1 = _runX1[i];
      final int firstRow = y - reach < 0 ? 0 : y - reach;
      for (int row = firstRow; row <= y; row++) {
        final int end = row == y ? i : rowStart[row + 1];
        for (int j = rowStart[row]; j < end; j++) {
          if (x0 - _runX1[j] <= reach && _runX0[j] - x1 <= reach) {
            _union(i, j);
          }
        }
      }
    }

    // 3. Add up the measurements of every patch.
    for (int i = 0; i < runs; i++) {
      _head[i] = -1;
      _count[i] = 0;
      _minX[i] = 1 << 30;
      _maxX[i] = -1;
      _minY[i] = 1 << 30;
      _maxY[i] = -1;
      _sx[i] = 0;
      _sy[i] = 0;
      _sxx[i] = 0;
      _syy[i] = 0;
      _sxy[i] = 0;
    }
    for (int i = 0; i < runs; i++) {
      final int root = _find(i);
      final int y = _runY[i];
      final int x0 = _runX0[i];
      final int x1 = _runX1[i];
      final int length = x1 - x0 + 1;
      final double sumX = (x0 + x1) * length / 2.0;
      final double sumXX = _squareSum(x1) - _squareSum(x0 - 1);
      _count[root] += length;
      if (x0 < _minX[root]) {
        _minX[root] = x0;
      }
      if (x1 > _maxX[root]) {
        _maxX[root] = x1;
      }
      if (y < _minY[root]) {
        _minY[root] = y;
      }
      if (y > _maxY[root]) {
        _maxY[root] = y;
      }
      _sx[root] += sumX;
      _sy[root] += y * length;
      _sxx[root] += sumXX;
      _syy[root] += y.toDouble() * y * length;
      _sxy[root] += y * sumX;
      _next[i] = _head[root];
      _head[root] = i;
    }

    // 4. Measure the patches that could be a ball.
    final int maxExtent = math.max(5, (maxExtentFraction * height).round());
    final int maxArea = math.max(200, (maxAreaFraction * width * height).round());
    final List<Blob> blobs = <Blob>[];
    for (int root = 0; root < runs && blobs.length < maxBlobs; root++) {
      if (_parent[root] != root) {
        continue;
      }
      final int n = _count[root];
      if (n < minArea || n > maxArea) {
        continue;
      }
      final int boxWidth = _maxX[root] - _minX[root] + 1;
      final int boxHeight = _maxY[root] - _minY[root] + 1;
      if (boxWidth > maxExtent || boxHeight > maxExtent) {
        continue;
      }
      final Blob blob = _measure(root, n, diff, width);
      if (!blob.isStrip) {
        blobs.add(blob);
      }
    }
    return blobs;
  }

  Blob _measure(int root, int n, Uint8List diff, int width) {
    final Int32List histogram = _histogram;
    histogram.fillRange(0, 256, 0);
    int sumDiff = 0;
    int peak = 0;
    for (int run = _head[root]; run >= 0; run = _next[run]) {
      final int base = _runY[run] * width;
      for (int x = _runX0[run]; x <= _runX1[run]; x++) {
        final int value = diff[base + x];
        histogram[value] += 1;
        sumDiff += value;
        if (value > peak) {
          peak = value;
        }
      }
    }
    final int target = (0.9 * n).ceil();
    int cumulative = 0;
    int p90 = 0;
    for (int v = 0; v < 256; v++) {
      cumulative += histogram[v];
      if (cumulative >= target) {
        p90 = v;
        break;
      }
    }
    final int halfFrom = (p90 + 1) ~/ 2;
    int half = 0;
    for (int v = halfFrom; v < 256; v++) {
      half += histogram[v];
    }

    final double meanX = _sx[root] / n;
    final double meanY = _sy[root] / n;
    // One pixel is a square of side 1: add its own variance (1/12) so a single pixel has a size.
    final double cxx = _sxx[root] / n - meanX * meanX + 1 / 12;
    final double cyy = _syy[root] / n - meanY * meanY + 1 / 12;
    final double cxy = _sxy[root] / n - meanX * meanY;
    final double trace = cxx + cyy;
    final double spread = math.sqrt(math.max(0.0, (cxx - cyy) * (cxx - cyy) / 4 + cxy * cxy));
    final double lambda1 = trace / 2 + spread;
    final double lambda2 = math.max(trace / 2 - spread, 1 / 12);
    return Blob(
      area: n,
      cx: meanX + 0.5,
      cy: meanY + 0.5,
      major: 4 * math.sqrt(lambda1),
      minor: 4 * math.sqrt(lambda2),
      meanDiff: sumDiff / n,
      peakDiff: peak,
      p90Diff: p90,
      halfArea: half,
      left: _minX[root],
      top: _minY[root],
      right: _maxX[root],
      bottom: _maxY[root],
    );
  }

  int _find(int index) {
    int root = index;
    while (_parent[root] != root) {
      root = _parent[root];
    }
    int walker = index;
    while (_parent[walker] != root) {
      final int up = _parent[walker];
      _parent[walker] = root;
      walker = up;
    }
    return root;
  }

  void _union(int a, int b) {
    final int rootA = _find(a);
    final int rootB = _find(b);
    if (rootA == rootB) {
      return;
    }
    // The smaller index stays the root, which keeps the patches in raster order.
    if (rootA < rootB) {
      _parent[rootB] = rootA;
    } else {
      _parent[rootA] = rootB;
    }
  }

  /// `0^2 + 1^2 + ... + m^2` (0 for m < 0).
  static double _squareSum(int m) {
    if (m < 0) {
      return 0;
    }
    final double d = m.toDouble();
    return d * (d + 1) * (2 * d + 1) / 6;
  }
}
