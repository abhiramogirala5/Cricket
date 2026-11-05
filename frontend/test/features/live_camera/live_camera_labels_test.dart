import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/zoom_advice.dart';
import 'package:gully_umpire/features/live_camera/live_camera_labels.dart';

void main() {
  group('watchLabel', () {
    test('every state has its own plain-words label', () {
      final Set<String> labels = <String>{
        for (final LiveWatchState state in LiveWatchState.values) watchLabel(state),
      };
      expect(labels, hasLength(LiveWatchState.values.length));
      expect(watchLabel(LiveWatchState.watching), contains('Ready'));
      expect(watchLabel(LiveWatchState.tracking), contains('ball'));
    });
  });

  group('bannerKindFor', () {
    test('maps the framing level to a colour family', () {
      expect(bannerKindFor(FramingLevel.good), BannerKind.success);
      expect(bannerKindFor(FramingLevel.fair), BannerKind.warning);
      expect(bannerKindFor(FramingLevel.poor), BannerKind.error);
      expect(bannerKindFor(FramingLevel.unknown), BannerKind.info);
    });
  });

  group('speedLine', () {
    test('is empty until something has been measured', () {
      expect(speedLine(fps: 0, latencyMs: 0), isEmpty);
      expect(speedLine(fps: -1, latencyMs: 20), isEmpty);
    });

    test('shows the rate, and the delay once it is known', () {
      expect(speedLine(fps: 29.6, latencyMs: 0), '30 pictures a second');
      expect(speedLine(fps: 30, latencyMs: 27.6), '30 pictures a second, 28 ms delay');
    });
  });

  group('isStruggling', () {
    test('is false before enough pictures have been looked at', () {
      expect(
        isStruggling(fps: 30, latencyMs: 500, framesAnalysed: 29, framesDropped: 100),
        isFalse,
      );
    });

    test('is false when nothing is measured', () {
      expect(isStruggling(fps: 0, latencyMs: 500, framesAnalysed: 100, framesDropped: 0), isFalse);
    });

    test('is true when a picture takes much longer than the gap between pictures', () {
      // 30 pictures a second is 33 ms apart; 2.5 times that is 83 ms.
      expect(isStruggling(fps: 30, latencyMs: 90, framesAnalysed: 100, framesDropped: 0), isTrue);
      expect(isStruggling(fps: 30, latencyMs: 80, framesAnalysed: 100, framesDropped: 0), isFalse);
    });

    test('is true when a quarter or more of the pictures are skipped', () {
      expect(isStruggling(fps: 30, latencyMs: 20, framesAnalysed: 70, framesDropped: 30), isTrue);
      expect(isStruggling(fps: 30, latencyMs: 20, framesAnalysed: 90, framesDropped: 10), isFalse);
    });
  });
}
