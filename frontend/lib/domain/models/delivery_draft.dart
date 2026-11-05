import 'package:gully_umpire/domain/models/enums.dart';

/// What the scorer enters for one ball. Everything derived (sequence, over, ball number)
/// is added by `ScoreEngine.buildDelivery`.
final class DeliveryDraft {
  const DeliveryDraft({
    required this.bowlerId,
    required this.strikerId,
    this.nonStrikerId,
    this.runsBat = 0,
    this.runsExtras = 0,
    this.isWide = false,
    this.isNoBall = false,
    this.isBye = false,
    this.isLegBye = false,
    this.isWicket = false,
    this.dismissalType,
    this.dismissedPlayerId,
    this.wicketDetectionId,
    this.speedKmph,
    this.speedConfidence,
    this.ballTrackingConfidence,
    this.poseTrackingConfidence,
    this.wicketTrackingConfidence,
  });

  final String bowlerId;
  final String strikerId;
  final String? nonStrikerId;
  final int runsBat;
  final int runsExtras;
  final bool isWide;
  final bool isNoBall;
  final bool isBye;
  final bool isLegBye;
  final bool isWicket;
  final DismissalType? dismissalType;
  final String? dismissedPlayerId;
  final String? wicketDetectionId;
  final double? speedKmph;
  final double? speedConfidence;
  final double? ballTrackingConfidence;
  final double? poseTrackingConfidence;
  final double? wicketTrackingConfidence;

  bool get isLegal => !isWide && !isNoBall;

  /// The same ball with the measurements of the umpiring assistant added. Values that are not
  /// given keep what the draft already had.
  DeliveryDraft withMeasurements({
    String? wicketDetectionId,
    double? speedKmph,
    double? speedConfidence,
    double? ballTrackingConfidence,
    double? poseTrackingConfidence,
    double? wicketTrackingConfidence,
  }) =>
      DeliveryDraft(
        bowlerId: bowlerId,
        strikerId: strikerId,
        nonStrikerId: nonStrikerId,
        runsBat: runsBat,
        runsExtras: runsExtras,
        isWide: isWide,
        isNoBall: isNoBall,
        isBye: isBye,
        isLegBye: isLegBye,
        isWicket: isWicket,
        dismissalType: dismissalType,
        dismissedPlayerId: dismissedPlayerId,
        wicketDetectionId: wicketDetectionId ?? this.wicketDetectionId,
        speedKmph: speedKmph ?? this.speedKmph,
        speedConfidence: speedConfidence ?? this.speedConfidence,
        ballTrackingConfidence: ballTrackingConfidence ?? this.ballTrackingConfidence,
        poseTrackingConfidence: poseTrackingConfidence ?? this.poseTrackingConfidence,
        wicketTrackingConfidence: wicketTrackingConfidence ?? this.wicketTrackingConfidence,
      );
}
