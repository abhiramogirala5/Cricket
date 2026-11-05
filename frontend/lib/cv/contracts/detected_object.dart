import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

/// One detection from an object detector (spec §8 `DetectedObject`).
final class DetectedObject extends Equatable {
  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  /// One of the [SceneLabels] (or `cricket_ball` for a ball detector).
  final String label;

  /// Detector confidence 0..1.
  final double confidence;

  /// Normalised 0..1 box.
  final BoundingBox boundingBox;

  @override
  List<Object?> get props => <Object?>[label, confidence, boundingBox];

  @override
  String toString() => 'DetectedObject($label, ${confidence.toStringAsFixed(2)}, $boundingBox)';
}

/// Object class names used by detectors (spec §17 dataset labels).
abstract final class SceneLabels {
  static const String ball = 'cricket_ball';
  static const String bat = 'cricket_bat';
  static const String stumps = 'traditional_stumps';
  static const String chair = 'chair';
  static const String bottle = 'bottle';
  static const String brick = 'brick';
  static const String cone = 'cone';
  static const String bucket = 'bucket';
  static const String bag = 'bag';
  static const String wallTarget = 'wall_target';
  static const String unknownObject = 'unknown_object';
  static const String person = 'person';
  static const String batsman = 'batsman';
  static const String bowler = 'bowler';

  /// Labels whose detections are merged into one wicket target when they are
  /// close together (three stumps, a stack of bricks, a row of bottles/cones).
  static const Set<String> clusterable = <String>{stumps, bottle, brick, cone};

  /// Lower-cases, trims and maps a few common aliases (`stumps`, `stump`) to
  /// the canonical label.
  static String normalize(String label) {
    final String lower = label.trim().toLowerCase();
    switch (lower) {
      case 'stumps':
      case 'stump':
      case 'wicket':
        return stumps;
      case 'ball':
        return ball;
      case 'bat':
        return bat;
      default:
        return lower;
    }
  }

  /// True for labels that denote a human (never a wicket candidate).
  static bool isPerson(String label) {
    final String normal = normalize(label);
    return normal == person || normal == batsman || normal == bowler;
  }

  /// The wicket family a detection label would form, or null when the label is
  /// not something that can act as a wicket (people, ball, bat, unknown names).
  static WicketFamily? familyForLabel(String label) {
    switch (normalize(label)) {
      case stumps:
        return WicketFamily.traditionalStumps;
      case chair:
        return WicketFamily.chair;
      case brick:
        return WicketFamily.brickStack;
      case bottle:
        return WicketFamily.bottleStack;
      case cone:
        return WicketFamily.coneStack;
      case bucket:
        return WicketFamily.bucket;
      case bag:
        return WicketFamily.bagOrObject;
      case wallTarget:
        return WicketFamily.wallTarget;
      case unknownObject:
        return WicketFamily.unknownPhysicalObject;
      default:
        return null;
    }
  }
}
