import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/scene/spatial_hash.dart';

void main() {
  group('boxGap', () {
    test('is zero for overlapping or touching boxes', () {
      final BoundingBox a = BoundingBox.fromLTRB(0, 0, 0.2, 0.2);
      expect(boxGap(a, BoundingBox.fromLTRB(0.1, 0.1, 0.3, 0.3)), 0);
      expect(boxGap(a, BoundingBox.fromLTRB(0.2, 0, 0.4, 0.2)), 0);
    });

    test('is the distance between the nearest edges', () {
      final BoundingBox a = BoundingBox.fromLTRB(0, 0, 0.2, 0.2);
      expect(boxGap(a, BoundingBox.fromLTRB(0.3, 0, 0.5, 0.2)), closeTo(0.1, 1e-12));
      expect(boxGap(a, BoundingBox.fromLTRB(0.5, 0.6, 0.7, 0.8)), closeTo(0.5, 1e-12));
    });
  });

  group('clusterBoxes', () {
    test('no boxes give no groups', () {
      expect(clusterBoxes(<BoundingBox>[], maxGap: 0.03), isEmpty);
    });

    test('nearby boxes are grouped and far ones are not', () {
      final List<List<int>> groups = clusterBoxes(
        <BoundingBox>[
          BoundingBox.fromLTRB(0.40, 0.40, 0.42, 0.50),
          BoundingBox.fromLTRB(0.43, 0.40, 0.45, 0.50),
          BoundingBox.fromLTRB(0.80, 0.40, 0.82, 0.50),
        ],
        maxGap: 0.03,
      );
      expect(groups, <List<int>>[
        <int>[0, 1],
        <int>[2],
      ]);
    });

    test('boxes are linked through a chain of neighbours', () {
      final List<List<int>> groups = clusterBoxes(
        <BoundingBox>[
          BoundingBox.fromLTRB(0.10, 0.4, 0.12, 0.5),
          BoundingBox.fromLTRB(0.14, 0.4, 0.16, 0.5),
          BoundingBox.fromLTRB(0.18, 0.4, 0.20, 0.5),
        ],
        maxGap: 0.03,
      );
      expect(groups, <List<int>>[
        <int>[0, 1, 2],
      ]);
    });

    test('every index appears exactly once, groups ordered by their smallest index', () {
      final List<List<int>> groups = clusterBoxes(
        <BoundingBox>[
          BoundingBox.fromLTRB(0.80, 0.4, 0.82, 0.5),
          BoundingBox.fromLTRB(0.10, 0.4, 0.12, 0.5),
          BoundingBox.fromLTRB(0.81, 0.4, 0.83, 0.5),
          BoundingBox.fromLTRB(0.11, 0.4, 0.13, 0.5),
        ],
        maxGap: 0.03,
      );
      expect(groups, <List<int>>[
        <int>[0, 2],
        <int>[1, 3],
      ]);
    });
  });
}
