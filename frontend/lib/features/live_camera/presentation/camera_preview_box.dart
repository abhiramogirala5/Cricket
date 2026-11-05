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
  });

  final FrameSource? source;
  final Widget overlay;

  /// The preview is at most this tall (the picture of a phone held upright is taller than wide).
  final double maxHeight;

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
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: picture,
        ),
      ),
    );
  }
}
