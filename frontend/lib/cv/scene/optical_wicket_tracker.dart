import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';
import 'package:gully_umpire/features/live_camera/camera_distance.dart';

/// The result of optical computer vision wicket detection.
final class OpticalWicketResult extends Equatable {
  const OpticalWicketResult({
    required this.corners,
    required this.confidence,
    required this.isOpticallyRefined,
    required this.family,
    this.statusMessage = '',
  });

  /// The 4 polygon corners in normalized screen coordinates:
  /// [topLeft, topRight, bottomRight, bottomLeft].
  final List<Point2D> corners;

  /// Optical detection confidence (0.0 to 1.0).
  final double confidence;

  /// Whether the corners were refined by visual edge/contrast analysis
  /// (true) or derived from geometric perspective priors (false).
  final bool isOpticallyRefined;

  final WicketFamily family;

  /// Human-readable explanation of the optical lock.
  final String statusMessage;

  @override
  List<Object?> get props => <Object?>[corners, confidence, isOpticallyRefined, family, statusMessage];
}

/// The result of spatial anchor tracking across consecutive frames.
final class AnchorTrackingResult extends Equatable {
  const AnchorTrackingResult({
    required this.corners,
    required this.displacement,
    required this.confidence,
    required this.hasMoved,
  });

  final List<Point2D> corners;

  /// Net normalized camera displacement (dx, dy) detected in this frame.
  final Point2D displacement;

  /// Tracking confidence (0.0 to 1.0).
  final double confidence;

  /// True if camera movement shifted the polygon.
  final bool hasMoved;

  @override
  List<Object?> get props => <Object?>[corners, displacement, confidence, hasMoved];
}

/// A visual anchor feature point and its grayscale template patch.
final class _AnchorPoint {
  _AnchorPoint({
    required this.u,
    required this.v,
    required this.patch,
  });

  double u;
  double v;
  final Uint8List patch;
}

/// Computer vision pipeline for:
/// 1. Detecting physical stumps / chairs via vertical edge profiling and boundary gradients.
/// 2. Tracking camera motion (spatial anchor) so the marked wicket remains locked on the
///    physical object in world space when the camera pans, tilts, or shakes.
final class OpticalWicketTracker {
  OpticalWicketTracker({
    this.searchRadiusPixels = 16,
    this.patchRadius = 5,
  });

  /// Maximum pixel displacement searched between consecutive frames.
  final int searchRadiusPixels;

  /// Radius around feature point for correlation patch ((2*r + 1) x (2*r + 1)).
  final int patchRadius;

  List<Point2D>? _corners;
  List<_AnchorPoint>? _anchors;
  bool _isLocked = false;

  bool get isAnchorLocked => _isLocked && _corners != null && _anchors != null;
  List<Point2D>? get currentCorners => _corners != null ? List<Point2D>.unmodifiable(_corners!) : null;

  /// Analyzes the visual pixels in [frame] around [searchCenter] to detect the true physical
  /// boundaries of [family] (e.g. 3 vertical stumps or chair uprights).
  OpticalWicketResult detectOrRefineWicket({
    required LumaFrame frame,
    Point2D? searchCenter,
    WicketFamily family = WicketFamily.traditionalStumps,
    double? targetDistanceFeet,
    double zoom = 1.0,
  }) {
    final Point2D center = searchCenter ?? const Point2D(0.50, 0.65);
    final List<Point2D> fallbackCorners = smartWicketCorners(
      family: family,
      centerX: center.x,
      groundY: center.y,
      targetDistanceFeet: targetDistanceFeet,
      zoom: zoom,
    );

    final int width = frame.width;
    final int height = frame.height;
    if (width < 32 || height < 32) {
      return OpticalWicketResult(
        corners: fallbackCorners,
        confidence: 0.50,
        isOpticallyRefined: false,
        family: family,
        statusMessage: 'Resolution too low for optical edge profiling',
      );
    }

    // Determine perspective prior bounds in pixel coordinates
    final double priorW = (fallbackCorners[1].x - fallbackCorners[0].x).abs() * width;
    final double priorH = (fallbackCorners[2].y - fallbackCorners[0].y).abs() * height;

    final int cx = (center.x * width).round().clamp(10, width - 10);
    final int cy = (center.y * height).round().clamp(10, height - 10);

    // Search window: horizontal expansion +/- 1.4x prior width, vertical +/- 1.2x prior height
    final int roiHalfW = (priorW * 0.70).round().clamp(8, width ~/ 3);
    final int roiTopH = (priorH * 0.85).round().clamp(12, height ~/ 2);
    final int roiBottomH = (priorH * 0.35).round().clamp(6, height ~/ 4);

    final int xMin = math.max(1, cx - roiHalfW);
    final int xMax = math.min(width - 2, cx + roiHalfW);
    final int yMin = math.max(1, cy - roiTopH);
    final int yMax = math.min(height - 2, cy + roiBottomH);

    final int roiWidth = xMax - xMin;
    final int roiHeight = yMax - yMin;
    if (roiWidth < 6 || roiHeight < 10) {
      return OpticalWicketResult(
        corners: fallbackCorners,
        confidence: 0.55,
        isOpticallyRefined: false,
        family: family,
        statusMessage: 'Target corridor locked',
      );
    }

    final Uint8List pixels = frame.pixels;

    // Step 1: Vertical edge profile (horizontal gradient |I(x+1, y) - I(x-1, y)|)
    // Stumps and chair uprights create strong vertical gradient columns.
    final List<int> colGrad = List<int>.filled(roiWidth, 0);
    int totalGrad = 0;

    for (int y = yMin; y <= yMax; y += 2) {
      final int rowOffset = y * width;
      for (int x = xMin; x < xMax; x++) {
        final int g = (pixels[rowOffset + x + 1] - pixels[rowOffset + x - 1]).abs();
        final int localIdx = x - xMin;
        colGrad[localIdx] += g;
        totalGrad += g;
      }
    }

    final double meanGrad = totalGrad / (roiWidth * math.max(1, (roiHeight ~/ 2)));

    // Find outer vertical edge peaks that enclose the wicket
    int peakLeft = -1;
    int peakRight = -1;
    final int gradThreshold = math.max(12, (meanGrad * 1.35).round());

    for (int i = 0; i < roiWidth; i++) {
      if (colGrad[i] >= gradThreshold) {
        if (peakLeft == -1) peakLeft = i;
        peakRight = i;
      }
    }

    final bool edgesFound = totalGrad > 60 && peakLeft != -1 && peakRight > peakLeft && (peakRight - peakLeft) >= 3;

    final double detectedLeft;
    final double detectedRight;
    if (edgesFound) {
      detectedLeft = ((xMin + peakLeft) / width).clamp(0.05, 0.95);
      detectedRight = ((xMin + peakRight) / width).clamp(detectedLeft + 0.02, 0.95);
    } else {
      detectedLeft = fallbackCorners[0].x;
      detectedRight = fallbackCorners[1].x;
    }

    // Step 2: Row edge profile along detected columns to find top (bails/top bar) and base (ground)
    final int scanX0 = ((detectedLeft * width).round()).clamp(1, width - 2);
    final int scanX1 = ((detectedRight * width).round()).clamp(scanX0 + 1, width - 2);

    final List<int> rowGrad = List<int>.filled(roiHeight, 0);
    for (int y = yMin; y < yMax; y++) {
      int rSum = 0;
      final int rowAbove = (y - 1) * width;
      final int rowBelow = (y + 1) * width;
      for (int x = scanX0; x <= scanX1; x++) {
        rSum += (pixels[rowBelow + x] - pixels[rowAbove + x]).abs();
      }
      rowGrad[y - yMin] = rSum;
    }

    // Top is near the start of high vertical edges; base is where vertical edges stop
    int bestTopY = yMin;
    int bestBaseY = yMax;

    int maxRowGrad = 0;
    for (int i = 0; i < roiHeight; i++) {
      if (rowGrad[i] > maxRowGrad) {
        maxRowGrad = rowGrad[i];
      }
    }

    final int rowThresh = (maxRowGrad * 0.40).round();
    for (int i = 0; i < roiHeight; i++) {
      if (rowGrad[i] >= rowThresh) {
        bestTopY = yMin + i;
        break;
      }
    }
    for (int i = roiHeight - 1; i >= 0; i--) {
      if (rowGrad[i] >= rowThresh) {
        bestBaseY = yMin + i;
        break;
      }
    }

    // Maintain plausible aspect ratio bounds
    double detectedTop = (bestTopY / height).clamp(0.05, 0.90);
    double detectedBottom = (bestBaseY / height).clamp(detectedTop + 0.04, 0.98);

    final double detectedHeight = detectedBottom - detectedTop;
    final double detectedWidth = detectedRight - detectedLeft;

    // Guard against noise collapse or expansion
    if (detectedHeight < priorH / (2.0 * height) || detectedHeight > (priorH * 2.2) / height) {
      detectedBottom = (cy / height).clamp(0.15, 0.98);
      detectedTop = (detectedBottom - (priorH / height)).clamp(0.05, 0.90);
    }

    final double midX = (detectedLeft + detectedRight) / 2;
    final double finalW = (detectedWidth).clamp(priorW * 0.5 / width, priorW * 1.5 / width);
    final double left = (midX - finalW / 2).clamp(0.02, 0.98);
    final double right = (midX + finalW / 2).clamp(left + 0.02, 0.98);

    final List<Point2D> refinedCorners = <Point2D>[
      Point2D(left, detectedTop),
      Point2D(right, detectedTop),
      Point2D(right, detectedBottom),
      Point2D(left, detectedBottom),
    ];

    final double confidence = edgesFound ? 0.92 : 0.65;
    final String message = edgesFound
        ? 'Physical edges locked (${family.label})'
        : 'Aligned with pitch corridor (${family.label})';

    return OpticalWicketResult(
      corners: refinedCorners,
      confidence: confidence,
      isOpticallyRefined: edgesFound,
      family: family,
      statusMessage: message,
    );
  }

  /// Locks spatial anchor tracking onto [corners] in [frame].
  /// As the phone camera moves, subsequent calls to [updateAnchor] will track the camera's
  /// ego-motion and keep the polygon locked onto the real-world object.
  void lockAnchor(List<Point2D> corners, LumaFrame frame) {
    if (corners.length < 4) return;
    _corners = List<Point2D>.of(corners);

    final int width = frame.width;
    final int height = frame.height;
    final Uint8List pixels = frame.pixels;

    // Anchor feature points in normalized frame space:
    // 4 corners, center, bottom-middle, and nearby ground texture
    final double midX = (corners[0].x + corners[1].x) / 2;
    final double midY = (corners[0].y + corners[2].y) / 2;
    final double baseY = corners[2].y;

    final List<Point2D> anchorLocs = <Point2D>[
      corners[0], // top-left
      corners[1], // top-right
      corners[2], // bottom-right
      corners[3], // bottom-left
      Point2D(midX, midY), // center
      Point2D(midX, baseY), // base center (ground contact)
      Point2D(midX - 0.05, baseY + 0.03), // ground left
      Point2D(midX + 0.05, baseY + 0.03), // ground right
    ];

    final int pDiam = 2 * patchRadius + 1;
    final List<_AnchorPoint> anchors = <_AnchorPoint>[];

    for (final Point2D p in anchorLocs) {
      final int u = (p.x * width).round();
      final int v = (p.y * height).round();

      if (u < patchRadius || u >= width - patchRadius || v < patchRadius || v >= height - patchRadius) {
        continue;
      }

      final Uint8List patch = Uint8List(pDiam * pDiam);
      int pIdx = 0;
      for (int dy = -patchRadius; dy <= patchRadius; dy++) {
        final int rOffset = (v + dy) * width;
        for (int dx = -patchRadius; dx <= patchRadius; dx++) {
          patch[pIdx++] = pixels[rOffset + u + dx];
        }
      }

      anchors.add(_AnchorPoint(u: u.toDouble(), v: v.toDouble(), patch: patch));
    }

    _anchors = anchors;
    _isLocked = anchors.isNotEmpty;
  }

  /// Tracks frame-to-frame camera ego-motion (optical displacement) and updates polygon corners
  /// so they stay glued to the physical stumps in 3D world space.
  AnchorTrackingResult updateAnchor(LumaFrame frame) {
    final List<Point2D>? corners = _corners;
    final List<_AnchorPoint>? anchors = _anchors;

    if (!_isLocked || corners == null || anchors == null || anchors.isEmpty) {
      return AnchorTrackingResult(
        corners: corners ?? const <Point2D>[],
        displacement: const Point2D(0, 0),
        confidence: 0.0,
        hasMoved: false,
      );
    }

    final int width = frame.width;
    final int height = frame.height;
    final Uint8List pixels = frame.pixels;
    final int pDiam = 2 * patchRadius + 1;
    final int pCount = pDiam * pDiam;

    final List<int> dispX = <int>[];
    final List<int> dispY = <int>[];

    for (final _AnchorPoint a in anchors) {
      final int u0 = a.u.round();
      final int v0 = a.v.round();

      if (u0 < patchRadius + searchRadiusPixels ||
          u0 >= width - patchRadius - searchRadiusPixels ||
          v0 < patchRadius + searchRadiusPixels ||
          v0 >= height - patchRadius - searchRadiusPixels) {
        continue;
      }

      int bestSAD = 1 << 30;
      int bestDu = 0;
      int bestDv = 0;

      // Coarse-to-fine search in local neighborhood
      for (int dv = -searchRadiusPixels; dv <= searchRadiusPixels; dv += 2) {
        for (int du = -searchRadiusPixels; du <= searchRadiusPixels; du += 2) {
          int sad = 0;
          int pIdx = 0;
          for (int py = -patchRadius; py <= patchRadius; py++) {
            final int rOffset = (v0 + dv + py) * width;
            for (int px = -patchRadius; px <= patchRadius; px++) {
              final int diff = pixels[rOffset + u0 + du + px] - a.patch[pIdx++];
              sad += diff < 0 ? -diff : diff;
            }
          }
          if (sad < bestSAD) {
            bestSAD = sad;
            bestDu = du;
            bestDv = dv;
          }
        }
      }

      // Fine search around best coarse match (+/- 1 pixel)
      final int coarseDu = bestDu;
      final int coarseDv = bestDv;
      for (int dv = coarseDv - 1; dv <= coarseDv + 1; dv++) {
        for (int du = coarseDu - 1; du <= coarseDu + 1; du++) {
          int sad = 0;
          int pIdx = 0;
          for (int py = -patchRadius; py <= patchRadius; py++) {
            final int rOffset = (v0 + dv + py) * width;
            for (int px = -patchRadius; px <= patchRadius; px++) {
              final int diff = pixels[rOffset + u0 + du + px] - a.patch[pIdx++];
              sad += diff < 0 ? -diff : diff;
            }
          }
          if (sad < bestSAD) {
            bestSAD = sad;
            bestDu = du;
            bestDv = dv;
          }
        }
      }

      // Check average pixel error (< 40 gray levels)
      if (bestSAD / pCount < 40.0) {
        dispX.add(bestDu);
        dispY.add(bestDv);
      }
    }

    if (dispX.isEmpty || dispY.isEmpty) {
      // Camera motion too fast or target occluded; maintain position
      return AnchorTrackingResult(
        corners: corners,
        displacement: const Point2D(0, 0),
        confidence: 0.30,
        hasMoved: false,
      );
    }

    // Robust median displacement
    dispX.sort();
    dispY.sort();
    final int medianDu = dispX[dispX.length ~/ 2];
    final int medianDv = dispY[dispY.length ~/ 2];

    final double normDx = medianDu / width;
    final double normDy = medianDv / height;

    final bool hasMoved = medianDu != 0 || medianDv != 0;

    if (hasMoved) {
      // Update polygon corners
      final List<Point2D> updatedCorners = <Point2D>[
        for (final Point2D p in corners)
          Point2D(
            (p.x + normDx).clamp(0.02, 0.98),
            (p.y + normDy).clamp(0.02, 0.98),
          ),
      ];
      _corners = updatedCorners;

      // Update anchor point coordinates
      for (final _AnchorPoint a in anchors) {
        a.u = (a.u + medianDu).clamp(patchRadius.toDouble(), (width - patchRadius - 1).toDouble());
        a.v = (a.v + medianDv).clamp(patchRadius.toDouble(), (height - patchRadius - 1).toDouble());
      }
    }

    final double confidence = (dispX.length / anchors.length).clamp(0.2, 1.0);

    return AnchorTrackingResult(
      corners: _corners!,
      displacement: Point2D(normDx, normDy),
      confidence: confidence,
      hasMoved: hasMoved,
    );
  }

  /// Unlocks the spatial anchor (e.g. while the user is manually dragging corners).
  void unlockAnchor() {
    _isLocked = false;
    _anchors = null;
  }
}
