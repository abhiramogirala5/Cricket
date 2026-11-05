import 'package:equatable/equatable.dart';

/// How well the camera is placed for measuring height.
enum FramingLevel {
  /// Not known yet (the batter has not been seen).
  unknown,

  /// Good enough.
  good,

  /// Usable, but a closer view would be better.
  fair,

  /// Too far away or too close for a trustworthy height.
  poor,
}

/// What to tell the person who holds or places the phone.
final class ZoomAdvice extends Equatable {
  const ZoomAdvice({
    required this.level,
    required this.message,
    this.ballPixelsAtBatter,
    this.batterShare,
  });

  final FramingLevel level;

  /// One short sentence in plain words.
  final String message;

  /// How many pixels wide the ball is when it reaches the batter, in the pictures that are analysed.
  final double? ballPixelsAtBatter;

  /// The batter's height as a share of the picture height (0..1).
  final double? batterShare;

  @override
  List<Object?> get props => <Object?>[level, message, ballPixelsAtBatter, batterShare];
}

/// Decides, from how big the batter looks, whether the camera is close (or zoomed in) enough.
///
/// The height of a ball at the batter is worked out from how many pixels it spans, so the ball must
/// be several pixels wide when it gets there. Its size at the batter is fixed by the batter's size
/// in the picture: a 7 cm ball next to a 1.7 m batter is `batterShare * pictureHeight * 0.042`
/// pixels wide.
abstract final class ZoomAdvisor {
  /// Ball pixels at the batter below which the height is mostly a guess.
  static const double poorBallPixels = 2.8;

  /// Ball pixels at the batter from which the view is good.
  static const double goodBallPixels = 4.5;

  /// A batter taller than this share of the picture is probably cut off.
  static const double tooCloseShare = 0.9;

  /// The advice for a batter of [batterShare] (0..1 of the picture height) in pictures that are
  /// [pictureHeightPx] pixels high, with a ball of [ballDiameterM] and a batter of [batterHeightM].
  static ZoomAdvice advise({
    required double? batterShare,
    required int pictureHeightPx,
    required double ballDiameterM,
    required double batterHeightM,
  }) {
    if (batterShare == null || !batterShare.isFinite || !(batterShare > 0) || pictureHeightPx <= 0) {
      return const ZoomAdvice(
        level: FramingLevel.unknown,
        message: 'Waiting to see the batter. Keep the whole batter in the picture.',
      );
    }
    final double ballPixels = batterShare * pictureHeightPx * ballDiameterM / batterHeightM;
    if (batterShare >= tooCloseShare) {
      return ZoomAdvice(
        level: FramingLevel.poor,
        message: 'Too close: the batter nearly fills the picture. Zoom out so the whole batter '
            'and the stumps are in view.',
        ballPixelsAtBatter: ballPixels,
        batterShare: batterShare,
      );
    }
    if (ballPixels < poorBallPixels) {
      return ZoomAdvice(
        level: FramingLevel.poor,
        message: 'Too far away: the ball will be only about ${ballPixels.toStringAsFixed(1)} pixels '
            'wide at the batter. Zoom in or move the phone closer until the batter fills about '
            'a third of the picture.',
        ballPixelsAtBatter: ballPixels,
        batterShare: batterShare,
      );
    }
    if (ballPixels < goodBallPixels) {
      return ZoomAdvice(
        level: FramingLevel.fair,
        message: 'Zoom in a little for a more reliable height '
            '(the ball is about ${ballPixels.toStringAsFixed(1)} pixels wide at the batter).',
        ballPixelsAtBatter: ballPixels,
        batterShare: batterShare,
      );
    }
    return ZoomAdvice(
      level: FramingLevel.good,
      message: 'The view is good: the ball will be about ${ballPixels.toStringAsFixed(1)} pixels wide '
          'at the batter.',
      ballPixelsAtBatter: ballPixels,
      batterShare: batterShare,
    );
  }
}
