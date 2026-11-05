import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/review/review_data.dart';

void main() {
  group('parsePathPoints', () {
    test('reads time, position and confidence', () {
      final List<PathPoint> points = parsePathPoints(<Object?>[
        <Object?>[0, 0.5, 0.2, 0.9],
        <Object?>[40.0, 0.52, 0.3, 0.8],
      ]);
      expect(points, const <PathPoint>[
        PathPoint(timeMs: 0, x: 0.5, y: 0.2, confidence: 0.9),
        PathPoint(timeMs: 40, x: 0.52, y: 0.3, confidence: 0.8),
      ]);
    });

    test('an empty path gives no points', () {
      expect(parsePathPoints(const <Object?>[]), isEmpty);
    });

    test('a missing or unreadable confidence counts as fully sure', () {
      final List<PathPoint> points = parsePathPoints(<Object?>[
        <Object?>[0, 0.5, 0.2],
        <Object?>[10, 0.5, 0.3, 'high'],
      ]);
      expect(points.map<double>((PathPoint p) => p.confidence), <double>[1.0, 1.0]);
    });

    test('whole numbers are read as decimals', () {
      final List<PathPoint> points = parsePathPoints(<Object?>[
        <Object?>[5, 1, 0, 1],
      ]);
      expect(points.single.x, 1.0);
      expect(points.single.y, 0.0);
    });

    test('confidence is kept between 0 and 1', () {
      final List<PathPoint> points = parsePathPoints(<Object?>[
        <Object?>[0, 0.5, 0.5, 1.5],
        <Object?>[1, 0.5, 0.5, -0.2],
        <Object?>[2, 0.5, 0.5, double.nan],
      ]);
      expect(points.map<double>((PathPoint p) => p.confidence), <double>[1.0, 0.0, 0.0]);
    });

    test('damaged points are skipped, good ones kept', () {
      final List<PathPoint> points = parsePathPoints(<Object?>[
        'not a point',
        <Object?>[1, 2],
        <Object?>[0, 'left', 0.1, 1],
        <Object?>['soon', 0.1, 0.1, 1],
        <Object?>[0, double.nan, 0.2, 1],
        <Object?>[0, 0.3, double.infinity, 1],
        null,
        <Object?>[7, 0.4, 0.6, 0.5],
      ]);
      expect(points, const <PathPoint>[
        PathPoint(timeMs: 7, x: 0.4, y: 0.6, confidence: 0.5),
      ]);
    });

    test('keeps the order of the stored path', () {
      final List<PathPoint> points = parsePathPoints(<Object?>[
        <Object?>[30, 0.1, 0.1, 1],
        <Object?>[10, 0.2, 0.2, 1],
      ]);
      expect(points.map<double>((PathPoint p) => p.timeMs), <double>[30, 10]);
    });
  });

  group('humanizeKey', () {
    test('turns snake_case into a sentence start', () {
      expect(humanizeKey('distance_m'), 'Distance m');
      expect(humanizeKey('LATERAL_DISTANCE'), 'Lateral distance');
      expect(humanizeKey('x'), 'X');
    });

    test('leaves a key with nothing readable as it is', () {
      expect(humanizeKey('___'), '___');
      expect(humanizeKey(''), '');
    });
  });

  group('friendlyResult', () {
    test('says "Not recorded" when there is nothing', () {
      expect(friendlyResult(null), 'Not recorded');
      expect(friendlyResult(''), 'Not recorded');
      expect(friendlyResult('   '), 'Not recorded');
    });

    test('knows the results the assistant and scorer use', () {
      expect(friendlyResult('WIDE'), 'Wide');
      expect(friendlyResult('NOT_WIDE'), 'Not a wide');
      expect(friendlyResult('NO_BALL'), 'No-ball');
      expect(friendlyResult('LEGAL'), 'Legal ball');
      expect(friendlyResult('INCONCLUSIVE'), 'Not sure');
      expect(friendlyResult('OUT'), 'Out');
      expect(friendlyResult('NOT_OUT'), 'Not out');
    });

    test('humanizes anything else', () {
      expect(friendlyResult('PITCHING_OUTSIDE_LEG'), 'Pitching outside leg');
    });
  });

  test('decisionSourceLabel names who made the call', () {
    expect(decisionSourceLabel(DecisionSource.aiAssist), 'Assistant');
    expect(decisionSourceLabel(DecisionSource.manual), 'Umpire');
  });

  group('evidenceLines', () {
    test('is empty without evidence', () {
      expect(evidenceLines(null), isEmpty);
      expect(evidenceLines(const <String, Object?>{}), isEmpty);
    });

    test('shows numbers, yes/no and short texts, and drops the rest', () {
      final List<({String label, String value})> lines = evidenceLines(<String, Object?>{
        'distance_m': 1.4,
        'count': 3,
        'is_close': true,
        'is_far': false,
        'note': 'ok',
        'nested': <String, Object?>{'a': 1},
        'empty_text': '',
        'a_list': <Object?>[1, 2],
        'missing': null,
      });
      expect(lines, <({String label, String value})>[
        (label: 'Distance m', value: '1.40'),
        (label: 'Count', value: '3'),
        (label: 'Is close', value: 'Yes'),
        (label: 'Is far', value: 'No'),
        (label: 'Note', value: 'ok'),
      ]);
    });

    test('whole decimals show without a fraction', () {
      final List<({String label, String value})> lines =
          evidenceLines(<String, Object?>{'width': 2.0});
      expect(lines.single.value, '2');
    });

    test('numbers that are not finite show a dash', () {
      final List<({String label, String value})> lines = evidenceLines(<String, Object?>{
        'a': double.nan,
        'b': double.infinity,
      });
      expect(lines.map<String>((({String label, String value}) l) => l.value), <String>['-', '-']);
    });

    test('long texts are cut to 60 characters', () {
      final String long = 'x' * 70;
      final List<({String label, String value})> lines =
          evidenceLines(<String, Object?>{'text': long});
      expect(lines.single.value, '${'x' * 57}...');
      expect(lines.single.value.length, 60);
    });

    test('stops at the maximum number of lines', () {
      final List<({String label, String value})> lines = evidenceLines(
        <String, Object?>{'a': 1, 'b': 2, 'c': 3},
        maxLines: 2,
      );
      expect(lines.map<String>((({String label, String value}) l) => l.label), <String>['A', 'B']);
    });
  });
}
