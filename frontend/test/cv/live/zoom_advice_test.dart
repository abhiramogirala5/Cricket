import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/zoom_advice.dart';

ZoomAdvice advise(double? share, {int height = 640, double ball = 0.072, double batter = 1.7}) {
  return ZoomAdvisor.advise(
    batterShare: share,
    pictureHeightPx: height,
    ballDiameterM: ball,
    batterHeightM: batter,
  );
}

void main() {
  group('ZoomAdvisor', () {
    test('without a batter in view there is no verdict yet', () {
      for (final double? share in <double?>[null, 0, -0.2, double.nan, double.infinity]) {
        final ZoomAdvice advice = advise(share);
        expect(advice.level, FramingLevel.unknown, reason: 'share $share');
        expect(advice.ballPixelsAtBatter, isNull);
        expect(advice.message, contains('batter'));
      }
      expect(advise(0.4, height: 0).level, FramingLevel.unknown);
    });

    test('a batter who fills a good part of the picture gives a good view', () {
      final ZoomAdvice advice = advise(0.5);

      // 0.5 * 640 * 0.072 / 1.7 = 13.6 pixels.
      expect(advice.level, FramingLevel.good);
      expect(advice.ballPixelsAtBatter, closeTo(0.5 * 640 * 0.072 / 1.7, 1e-9));
      expect(advice.batterShare, 0.5);
      expect(advice.message, contains('13.6'));
    });

    test('a small batter in the picture means the ball will be too small to measure', () {
      final ZoomAdvice advice = advise(0.1);

      // 0.1 * 640 * 0.072 / 1.7 = 2.7 pixels.
      expect(advice.level, FramingLevel.poor);
      expect(advice.message, contains('Too far'));
      expect(advice.message, contains('2.7'));
    });

    test('in between, a little more zoom is advised', () {
      final ZoomAdvice advice = advise(0.15);

      // 0.15 * 640 * 0.072 / 1.7 = 4.07 pixels: above 2.8 and below 4.5.
      expect(advice.level, FramingLevel.fair);
      expect(advice.message, contains('Zoom in a little'));
    });

    test('a batter who nearly fills the picture is too close', () {
      final ZoomAdvice advice = advise(0.95);

      expect(advice.level, FramingLevel.poor);
      expect(advice.message, contains('Too close'));
      expect(advice.ballPixelsAtBatter, isNotNull);
    });

    test('a taller picture makes the same batter share easier to measure', () {
      expect(advise(0.12, height: 320).level, FramingLevel.poor);
      expect(advise(0.12, height: 1280).level, FramingLevel.good);
    });

    test('a smaller ball needs a closer view', () {
      expect(advise(0.2, ball: 0.072).level, FramingLevel.good);
      expect(advise(0.2, ball: 0.02).level, isNot(FramingLevel.good));
    });

    test('a taller batter takes up more of the picture for the same ball size', () {
      expect(
        advise(0.2, batter: 2.1).ballPixelsAtBatter!,
        lessThan(advise(0.2, batter: 1.5).ballPixelsAtBatter!),
      );
    });

    test('advice with the same content is equal', () {
      expect(advise(0.5), advise(0.5));
      expect(advise(0.5), isNot(advise(0.1)));
    });
  });
}
