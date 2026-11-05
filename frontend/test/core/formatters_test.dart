import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/utils/formatters.dart';

void main() {
  group('formatOvers', () {
    test('writes legal balls in cricket notation', () {
      expect(formatOvers(0), '0.0');
      expect(formatOvers(5), '0.5');
      expect(formatOvers(6), '1.0');
      expect(formatOvers(13), '2.1');
      expect(formatOvers(120), '20.0');
    });
  });

  group('dates and times', () {
    // Local date-times, so the expectations hold in any time zone.
    test('formatDate writes day, short month and year', () {
      expect(formatDate(DateTime(2026, 10, 8)), '8 Oct 2026');
      expect(formatDate(DateTime(2027, 1, 31)), '31 Jan 2027');
      expect(formatDate(DateTime(2026, 12, 1)), '1 Dec 2026');
    });

    test('formatTime uses a 12-hour clock', () {
      expect(formatTime(DateTime(2026, 10, 8, 0, 5)), '12:05 AM');
      expect(formatTime(DateTime(2026, 10, 8, 9, 7)), '9:07 AM');
      expect(formatTime(DateTime(2026, 10, 8, 12)), '12:00 PM');
      expect(formatTime(DateTime(2026, 10, 8, 19, 5)), '7:05 PM');
      expect(formatTime(DateTime(2026, 10, 8, 23, 59)), '11:59 PM');
    });

    test('formatDateAndTime joins them', () {
      expect(formatDateAndTime(DateTime(2026, 10, 8, 19, 5)), '8 Oct 2026, 7:05 PM');
    });
  });

  group('numbers', () {
    test('formatPercent rounds to a whole percent', () {
      expect(formatPercent(0.874), '87%');
      expect(formatPercent(0), '0%');
      expect(formatPercent(1), '100%');
    });

    test('formatDecimal keeps one decimal place', () {
      expect(formatDecimal(133.333), '133.3');
      expect(formatDecimal(6), '6.0');
    });

    test('pluralize uses the singular only for exactly one', () {
      expect(pluralize(1, 'run'), '1 run');
      expect(pluralize(0, 'run'), '0 runs');
      expect(pluralize(2, 'run'), '2 runs');
      expect(pluralize(2, 'wicket', plural: 'wickets down'), '2 wickets down');
      expect(pluralize(1, 'wicket', plural: 'wickets down'), '1 wicket');
    });
  });
}
