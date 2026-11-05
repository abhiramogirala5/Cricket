import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';

void main() {
  group('ScanReadiness.fromConfidence', () {
    test('uses the documented thresholds', () {
      expect(ScanReadiness.fromConfidence(1.0), ScanReadiness.ready);
      expect(ScanReadiness.fromConfidence(0.85), ScanReadiness.ready);
      expect(ScanReadiness.fromConfidence(0.8499), ScanReadiness.moderate);
      expect(ScanReadiness.fromConfidence(0.70), ScanReadiness.moderate);
      expect(ScanReadiness.fromConfidence(0.6999), ScanReadiness.limited);
      expect(ScanReadiness.fromConfidence(0.50), ScanReadiness.limited);
      expect(ScanReadiness.fromConfidence(0.4999), ScanReadiness.reposition);
      expect(ScanReadiness.fromConfidence(0), ScanReadiness.reposition);
    });

    test('an unknown confidence means reposition', () {
      expect(ScanReadiness.fromConfidence(double.nan), ScanReadiness.reposition);
    });
  });

  group('what each level allows', () {
    test('automated umpiring needs ready or moderate', () {
      expect(ScanReadiness.ready.canStartAutomatedUmpiring, isTrue);
      expect(ScanReadiness.moderate.canStartAutomatedUmpiring, isTrue);
      expect(ScanReadiness.limited.canStartAutomatedUmpiring, isFalse);
      expect(ScanReadiness.reposition.canStartAutomatedUmpiring, isFalse);
    });

    test('wide assistance is available until the scan fails completely', () {
      expect(ScanReadiness.ready.allowsWideAssist, isTrue);
      expect(ScanReadiness.moderate.allowsWideAssist, isTrue);
      expect(ScanReadiness.limited.allowsWideAssist, isTrue);
      expect(ScanReadiness.reposition.allowsWideAssist, isFalse);
    });

    test('no-ball assistance needs a usable scan', () {
      expect(ScanReadiness.ready.allowsNoBallAssist, isTrue);
      expect(ScanReadiness.moderate.allowsNoBallAssist, isTrue);
      expect(ScanReadiness.limited.allowsNoBallAssist, isFalse);
      expect(ScanReadiness.reposition.allowsNoBallAssist, isFalse);
    });

    test('wicket based review needs a good wicket', () {
      expect(ScanReadiness.ready.allowsWicketDependentReview, isTrue);
      expect(ScanReadiness.moderate.allowsWicketDependentReview, isTrue);
      expect(ScanReadiness.limited.allowsWicketDependentReview, isFalse);
      expect(ScanReadiness.reposition.allowsWicketDependentReview, isFalse);
    });

    test('banners', () {
      expect(ScanReadiness.moderate.showsModerateBanner, isTrue);
      expect(ScanReadiness.ready.showsModerateBanner, isFalse);
      expect(ScanReadiness.reposition.asksToReposition, isTrue);
      expect(ScanReadiness.limited.asksToReposition, isFalse);
    });

    test('every level has a label and a message', () {
      for (final ScanReadiness level in ScanReadiness.values) {
        expect(level.label, isNotEmpty);
        expect(level.message, isNotEmpty);
      }
    });
  });
}
