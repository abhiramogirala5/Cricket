import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gully_umpire/cv/live/frame_source.dart';
import 'package:gully_umpire/cv/live/platform/camera_rig.dart';

/// The camera picture with [overlay] on top, sized so that the overlay covers exactly the
/// picture (positions 0..1 of the overlay are positions in the picture).
///
/// A phone camera shows its real preview; any other [FrameSource] (tests) shows a plain
/// placeholder of the same shape.
class CameraPreviewBox extends StatelessWidget {
  const CameraPreviewBox({
    super.key,
    required this.source,
    required this.overlay,
    this.maxHeight = 300,
    this.currentZoom,
    this.onZoomSelected,
  });

  final FrameSource? source;
  final Widget overlay;

  /// The preview is at most this tall (the picture of a phone held upright is taller than wide).
  final double maxHeight;

  /// Current camera zoom factor (1.0 = wide angle, 2.0 = 2x magnification).
  final double? currentZoom;

  /// Optional callback to change camera zoom level.
  final ValueChanged<double>? onZoomSelected;

  @override
  Widget build(BuildContext context) {
    final FrameSource? current = source;
    final Widget picture;
    if (current is CameraRig) {
      picture = CameraPreview(current.controller, child: overlay);
    } else {
      picture = AspectRatio(
        aspectRatio: 3 / 4,
        child: ColoredBox(
          color: Colors.black12,
          child: Stack(fit: StackFit.expand, children: <Widget>[overlay]),
        ),
      );
    }

    final double zoom = currentZoom ?? 1.0;
    final bool canZoom = onZoomSelected != null;

    final Widget content = Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        picture,
        if (canZoom)
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <double>[1.0, 1.5, 2.0, 3.0].map((double z) {
                  final bool active = (zoom - z).abs() < 0.15;
                  return GestureDetector(
                    onTap: () => onZoomSelected!(z),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${z == 1.0 ? '1' : z == 2.0 ? '2' : z == 3.0 ? '3' : z.toString()}x',
                        style: TextStyle(
                          color: active ? Colors.black : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: content,
        ),
      ),
    );
  }
}
