import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/zoom_advice.dart';

/// What the tracker is doing, in plain words for the status chip.
String watchLabel(LiveWatchState state) {
  switch (state) {
    case LiveWatchState.learning:
      return 'Learning the scene';
    case LiveWatchState.watching:
      return 'Ready: bowl when you like';
    case LiveWatchState.tracking:
      return 'Following the ball';
    case LiveWatchState.cooldown:
      return 'Ball finished';
  }
}

/// The colour family of a framing advice banner.
BannerKind bannerKindFor(FramingLevel level) {
  switch (level) {
    case FramingLevel.good:
      return BannerKind.success;
    case FramingLevel.fair:
      return BannerKind.warning;
    case FramingLevel.poor:
      return BannerKind.error;
    case FramingLevel.unknown:
      return BannerKind.info;
  }
}

/// "30 pictures a second, 28 ms delay" (or an empty text while nothing has been measured yet).
String speedLine({required double fps, required double latencyMs}) {
  if (fps <= 0) {
    return '';
  }
  final String rate = '${fps.round()} pictures a second';
  if (latencyMs <= 0) {
    return rate;
  }
  return '$rate, ${latencyMs.round()} ms delay';
}

/// True when the tracker cannot keep up with the camera: it takes noticeably longer than one
/// picture interval to look at a picture, or it has to skip many pictures.
bool isStruggling({
  required double fps,
  required double latencyMs,
  required int framesAnalysed,
  required int framesDropped,
}) {
  if (fps <= 0 || framesAnalysed < 30) {
    return false;
  }
  final double interval = 1000 / fps;
  final double dropShare = framesDropped / (framesAnalysed + framesDropped);
  return latencyMs > interval * 2.5 || dropShare > 0.25;
}
