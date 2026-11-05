import 'dart:math' as math;

import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/nv21_crop.dart';

/// Where to look for the batter, derived from the marked wicket.
///
/// The batter stands in front of his own wicket, so the region is centred on the wicket, a few
/// wicket-widths to each side, about four wicket-heights above it (a batter is roughly 2.4 times as
/// tall as a stump, and has a bat and a helmet) and a little below it (his feet are nearer the
/// camera than the stumps).
abstract final class BatterRegion {
  /// The region in pixels of the upright picture, or null when the wicket outline is unusable.
  static PixelRect? forWicket({
    required Polygon wicket,
    required int uprightWidth,
    required int uprightHeight,
    double halfWidthFactor = 2.5,
    double heightFactor = 1.5,
    double bottomFactor = 0.8,
    double topFactor = 4.0,
  }) {
    if (!wicket.isValid || uprightWidth <= 0 || uprightHeight <= 0) {
      return null;
    }
    final BoundingBox box = wicket.bounds;
    final double wicketWidth = box.width * uprightWidth;
    final double wicketHeight = box.height * uprightHeight;
    if (!(wicketWidth > 1) || !(wicketHeight > 1)) {
      return null;
    }
    final double centerX = box.centerX * uprightWidth;
    final double halfWidth = math.max(halfWidthFactor * wicketWidth, heightFactor * wicketHeight);
    final double top = box.top * uprightHeight - topFactor * wicketHeight;
    final double bottom = box.bottom * uprightHeight + bottomFactor * wicketHeight;

    int left = (centerX - halfWidth).floor();
    int right = (centerX + halfWidth).ceil();
    int topPx = top.floor();
    int bottomPx = bottom.ceil();
    left = left < 0 ? 0 : left;
    topPx = topPx < 0 ? 0 : topPx;
    right = right > uprightWidth ? uprightWidth : right;
    bottomPx = bottomPx > uprightHeight ? uprightHeight : bottomPx;
    if (right - left < 32 || bottomPx - topPx < 32) {
      return null;
    }
    return PixelRect(left, topPx, right, bottomPx);
  }
}
