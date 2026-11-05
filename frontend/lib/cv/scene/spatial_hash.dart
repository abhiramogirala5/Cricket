import 'dart:math' as math;

import 'package:gully_umpire/cv/geometry/bounding_box.dart';

/// A uniform grid over the unit square for neighbour queries (spec §11 "Spatial hash").
///
/// Items are stored by integer index under the cell of their point. A query looks at the cell of
/// the query point and its eight neighbours only, so clustering `n` items costs about `O(n)`
/// instead of comparing all pairs.
final class SpatialHash {
  SpatialHash(this.cellSize) : assert(cellSize > 0, 'cellSize must be positive');

  /// Side length of one cell (normalised units).
  final double cellSize;

  final Map<int, List<int>> _cells = <int, List<int>>{};

  /// Cell coordinate of [value].
  int cellOf(double value) => (value / cellSize).floor();

  /// One integer key for a cell. Cell coordinates are small, so this cannot overflow even on the web.
  static int keyOf(int cellX, int cellY) => (cellX + 0x8000) * 0x10000 + (cellY + 0x8000);

  /// Stores [index] at the point ([x], [y]).
  void insert(int index, double x, double y) {
    final int key = keyOf(cellOf(x), cellOf(y));
    final List<int>? bucket = _cells[key];
    if (bucket == null) {
      _cells[key] = <int>[index];
    } else {
      bucket.add(index);
    }
  }

  /// Indexes stored in the cell of ([x], [y]) and its eight neighbours.
  List<int> nearby(double x, double y) {
    final int cx = cellOf(x);
    final int cy = cellOf(y);
    final List<int> result = <int>[];
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        final List<int>? bucket = _cells[keyOf(cx + dx, cy + dy)];
        if (bucket != null) {
          result.addAll(bucket);
        }
      }
    }
    return result;
  }

  void clear() => _cells.clear();
}

/// Shortest distance between the edges of two boxes (0 when they touch or overlap).
double boxGap(BoundingBox a, BoundingBox b) {
  final double dx = math.max(0.0, math.max(a.left, b.left) - math.min(a.right, b.right));
  final double dy = math.max(0.0, math.max(a.top, b.top) - math.min(a.bottom, b.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

/// Groups boxes whose edges are at most [maxGap] apart, directly or through a chain of
/// neighbours (single-linkage clustering with a spatial hash and union-find).
///
/// Returns lists of indexes into [boxes]. Every index appears in exactly one group; groups are
/// ordered by their smallest index and each group lists its indexes in ascending order.
List<List<int>> clusterBoxes(List<BoundingBox> boxes, {required double maxGap}) {
  final int n = boxes.length;
  if (n == 0) {
    return <List<int>>[];
  }

  double largestSide = 0;
  for (final BoundingBox box in boxes) {
    largestSide = math.max(largestSide, math.max(box.width, box.height));
  }
  // Two boxes that are at most maxGap apart have centres at most (maxGap + largestSide) apart
  // along each axis, so a cell this large guarantees they share a cell or touching cells.
  final double cell = math.max(maxGap + largestSide, 1e-6);

  final SpatialHash hash = SpatialHash(cell);
  for (int i = 0; i < n; i++) {
    hash.insert(i, boxes[i].centerX, boxes[i].centerY);
  }

  final List<int> parent = List<int>.generate(n, (int i) => i);

  int find(int i) {
    int root = i;
    while (parent[root] != root) {
      root = parent[root];
    }
    int node = i;
    while (parent[node] != root) {
      final int next = parent[node];
      parent[node] = root;
      node = next;
    }
    return root;
  }

  void union(int a, int b) {
    final int rootA = find(a);
    final int rootB = find(b);
    if (rootA == rootB) {
      return;
    }
    if (rootA < rootB) {
      parent[rootB] = rootA;
    } else {
      parent[rootA] = rootB;
    }
  }

  for (int i = 0; i < n; i++) {
    for (final int j in hash.nearby(boxes[i].centerX, boxes[i].centerY)) {
      if (j > i && boxGap(boxes[i], boxes[j]) <= maxGap) {
        union(i, j);
      }
    }
  }

  final Map<int, List<int>> groups = <int, List<int>>{};
  for (int i = 0; i < n; i++) {
    final int root = find(i);
    final List<int>? group = groups[root];
    if (group == null) {
      groups[root] = <int>[i];
    } else {
      group.add(i);
    }
  }
  final List<List<int>> result = groups.values.toList();
  result.sort((List<int> a, List<int> b) => a.first.compareTo(b.first));
  return result;
}
