import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/tracking/speed_estimator.dart';
import 'package:gully_umpire/features/live_scoring/presentation/umpire_suggestion_card.dart';

void main() {
  group('ballSpeedLine', () {
    test('a measured speed says how far out it may be and where it comes from', () {
      final String line = ballSpeedLine(
        const SpeedEstimate(kmph: 78.4, confidence: 0.6, uncertaintyKmph: 8.6),
      );

      expect(line, contains('about 78 km/h'));
      expect(line, contains('give or take 9'));
      expect(line, contains('distance you entered'));
    });

    test('the give or take is never shown as zero', () {
      final String line = ballSpeedLine(
        const SpeedEstimate(kmph: 30, confidence: 0.6, uncertaintyKmph: 0.2),
      );

      expect(line, contains('give or take 1 '));
    });

    test('a speed that cannot say how far out it is says it is rough', () {
      final String line = ballSpeedLine(const SpeedEstimate(kmph: 60.2, confidence: 0.5));

      expect(line, 'Speed: about 60 km/h (a rough estimate).');
    });
  });
}
