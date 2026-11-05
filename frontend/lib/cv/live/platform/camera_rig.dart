import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:gully_umpire/cv/live/batter_pose_estimator.dart';
import 'package:gully_umpire/cv/live/frame_source.dart';

/// Why the phone's camera could not be used (already in plain words).
final class CameraRigException extends FrameSourceException {
  const CameraRigException(super.message);
}

/// The phone's back camera, delivering pictures to the live umpire session.
///
/// It asks for NV21 pictures (what the body-pose model reads and what holds the brightness plane
/// the ball tracker needs), at about 30 pictures per second, and turns each into a
/// [RawCameraFrame] that says how it has to be rotated to be upright.
final class CameraRig implements FrameSource {
  CameraRig._(this.controller, this._description, this._clock);

  /// The camera controller, for showing the preview.
  final CameraController controller;
  final CameraDescription _description;
  final Stopwatch _clock;

  bool _streaming = false;
  bool _disposed = false;

  @override
  double minZoom = 1;
  @override
  double maxZoom = 1;
  double _zoom = 1;

  @override
  double get zoom => _zoom;

  /// Opens the back camera. Throws a [CameraRigException] with a message for the person when the
  /// permission is refused or no camera is available.
  static Future<CameraRig> open({int fps = 30, ResolutionPreset preset = ResolutionPreset.high}) async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (error) {
      throw CameraRigException(_describe(error));
    }
    CameraDescription? back;
    for (final CameraDescription camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.back) {
        back = camera;
        break;
      }
    }
    if (back == null) {
      throw const CameraRigException('This phone has no back camera that the app can use.');
    }
    final CameraController controller = CameraController(
      back,
      preset,
      enableAudio: false,
      fps: fps,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    try {
      await controller.initialize();
    } on CameraException catch (error) {
      await controller.dispose();
      throw CameraRigException(_describe(error));
    }
    final CameraRig rig = CameraRig._(controller, back, Stopwatch()..start());
    try {
      rig.minZoom = await controller.getMinZoomLevel();
      rig.maxZoom = await controller.getMaxZoomLevel();
      rig._zoom = rig.minZoom;
    } on CameraException {
      // Zoom is optional.
    }
    return rig;
  }

  static String _describe(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'The camera permission was refused. Allow the camera for this app in the phone '
            'settings, then try again.';
      default:
        return 'The camera could not be opened (${error.description ?? error.code}).';
    }
  }

  /// Starts delivering pictures to [onFrame]. Pictures that are not in NV21 form are reported
  /// to [onProblem] (once) and skipped.
  @override
  Future<void> start(
    void Function(RawCameraFrame frame) onFrame, {
    void Function(String message)? onProblem,
  }) async {
    if (_streaming || _disposed) {
      return;
    }
    bool reported = false;
    await controller.startImageStream((CameraImage image) {
      if (_disposed) {
        return;
      }
      final RawCameraFrame? frame = _convert(image);
      if (frame == null) {
        if (!reported) {
          reported = true;
          onProblem?.call('This phone\'s camera does not deliver the picture format the app needs.');
        }
        return;
      }
      onFrame(frame);
    });
    _streaming = true;
    // A scene far away does not need the camera to hunt for focus (or to change its exposure,
    // which the tracker would see as the whole picture changing) while the ball flies past.
    unawaited(_lockFocusAndExposureSoon());
  }

  Future<void> _lockFocusAndExposureSoon() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (_disposed) {
      return;
    }
    try {
      await controller.setFocusMode(FocusMode.locked);
    } on Object {
      // Not every camera can lock its focus.
    }
    if (_disposed) {
      return;
    }
    try {
      await controller.setExposureMode(ExposureMode.locked);
    } on Object {
      // Not every camera can lock its exposure.
    }
  }

  RawCameraFrame? _convert(CameraImage image) {
    if (image.format.group != ImageFormatGroup.nv21 || image.planes.length != 1) {
      return null;
    }
    final Plane plane = image.planes.first;
    return RawCameraFrame(
      nv21: plane.bytes,
      width: image.width,
      height: image.height,
      rowStride: plane.bytesPerRow,
      rotationDegrees: uprightRotation(_description, controller.value.deviceOrientation),
      timestampMs: _clock.elapsedMilliseconds,
    );
  }

  /// The clockwise turn that makes a picture from [camera] upright when the phone is held in
  /// [orientation]. It follows how the phone is held, whichever way the app's own screen is turned.
  static int uprightRotation(CameraDescription camera, DeviceOrientation orientation) {
    final int device;
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        device = 0;
      case DeviceOrientation.landscapeLeft:
        device = 90;
      case DeviceOrientation.portraitDown:
        device = 180;
      case DeviceOrientation.landscapeRight:
        device = 270;
    }
    if (camera.lensDirection == CameraLensDirection.front) {
      return (camera.sensorOrientation + device) % 360;
    }
    return (camera.sensorOrientation - device + 360) % 360;
  }

  /// Sets the zoom (clamped to what the camera supports) and returns the value that was set.
  @override
  Future<double> setZoom(double level) async {
    final double clamped = level < minZoom ? minZoom : (level > maxZoom ? maxZoom : level);
    try {
      await controller.setZoomLevel(clamped);
      _zoom = clamped;
    } on CameraException {
      // Keep the old zoom.
    }
    return _zoom;
  }

  /// Stops the pictures and releases the camera. Safe to call more than once.
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_streaming) {
      _streaming = false;
      try {
        await controller.stopImageStream();
      } on CameraException {
        // Already stopped.
      }
    }
    await controller.dispose();
  }
}
