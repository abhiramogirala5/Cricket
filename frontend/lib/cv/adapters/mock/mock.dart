/// Stand-ins for the real vision models, driven by a [MockScenario]. They exist so that the app
/// and its tests can run without a trained model. Everything they return is marked `mock-`.
library;

export 'mock_audio_analyzer.dart';
export 'mock_ball_detector.dart';
export 'mock_camera.dart';
export 'mock_pose_estimator.dart';
export 'mock_scenario.dart';
export 'mock_scene_detector.dart';
