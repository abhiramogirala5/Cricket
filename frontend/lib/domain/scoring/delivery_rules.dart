import 'package:gully_umpire/domain/models/delivery_draft.dart';
import 'package:gully_umpire/domain/models/enums.dart';

/// Highest number of runs off the bat on one ball (overthrows included).
const int maxBatRunsPerBall = 7;

/// Highest number of extras on one ball (penalty run included).
const int maxExtraRunsPerBall = 10;

const int ballsPerOver = 6;

/// Everything validation rules 1-13 of docs/SCORING_RULES.md §2 need.
///
/// Player ids are compared with `==`; rules 1-13 never look them up anywhere.
final class DeliveryInput {
  const DeliveryInput({
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
  });

  factory DeliveryInput.fromDraft(DeliveryDraft draft) => DeliveryInput(
        strikerId: draft.strikerId,
        nonStrikerId: draft.nonStrikerId,
        runsBat: draft.runsBat,
        runsExtras: draft.runsExtras,
        isWide: draft.isWide,
        isNoBall: draft.isNoBall,
        isBye: draft.isBye,
        isLegBye: draft.isLegBye,
        isWicket: draft.isWicket,
        dismissalType: draft.dismissalType,
        dismissedPlayerId: draft.dismissedPlayerId,
      );

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

  /// 1 for wides and no-balls, otherwise 0.
  int get penaltyRuns => (isWide || isNoBall) ? 1 : 0;

  bool get isLegal => !isWide && !isNoBall;
}

/// Returns a short, user-presentable explanation of the first violated rule, or `null` when
/// the delivery is valid. Mirrors `validate_delivery` in `backend/app/services/scoring.py`
/// (same rules, same order); both are tested against `docs/scoring_test_vectors.json`.
String? validateDeliveryInput(DeliveryInput d) {
  final int penalty = d.penaltyRuns;
  final bool byes = d.isBye || d.isLegBye;

  // Rule 1
  if (d.runsBat < 0 || d.runsBat > maxBatRunsPerBall) {
    return 'Runs off the bat must be between 0 and $maxBatRunsPerBall.';
  }
  if (d.runsExtras < 0 || d.runsExtras > maxExtraRunsPerBall) {
    return 'Extras must be between 0 and $maxExtraRunsPerBall.';
  }
  // Rules 2-4
  if (d.isWide && d.isNoBall) {
    return 'A ball cannot be both a wide and a no-ball.';
  }
  if (d.isBye && d.isLegBye) {
    return 'A ball cannot be both a bye and a leg-bye.';
  }
  if (d.isWide && byes) {
    return 'All runs off a wide are wides. Byes and leg-byes are not allowed.';
  }
  // Rules 5-6
  if (d.isWide && d.runsBat > 0) {
    return 'A wide cannot have runs off the bat.';
  }
  if (byes && d.runsBat > 0) {
    return 'Byes and leg-byes cannot have runs off the bat.';
  }
  // Rules 7-9
  if (d.runsExtras < penalty) {
    return 'Wides and no-balls carry at least 1 extra run.';
  }
  if (byes && d.runsExtras < penalty + 1) {
    return 'A bye or leg-bye means at least one run was taken.';
  }
  if (!(d.isWide || d.isNoBall || byes) && d.runsExtras != 0) {
    return 'Extra runs need a wide, no-ball, bye or leg-bye.';
  }
  // Rule 10
  final DismissalType? dismissal = d.dismissalType;
  if (d.isWicket && dismissal == null) {
    return 'Choose how the batter got out.';
  }
  if (!d.isWicket && dismissal != null) {
    return 'A dismissal type is only allowed when a wicket falls.';
  }
  // Rules 11-12
  if (d.isWicket && dismissal != null) {
    if (d.isNoBall && dismissal != DismissalType.runOut) {
      return '${dismissal.label} is not allowed on a no-ball. Only a run-out counts.';
    }
    if (d.isWide &&
        dismissal != DismissalType.runOut &&
        dismissal != DismissalType.stumped &&
        dismissal != DismissalType.hitWicket) {
      return '${dismissal.label} is not allowed on a wide.';
    }
    final String? dismissedId = d.dismissedPlayerId;
    if (dismissedId == null) {
      return 'Choose which batter got out.';
    }
    final bool isStriker = dismissedId == d.strikerId;
    final bool isNonStriker = d.nonStrikerId != null && dismissedId == d.nonStrikerId;
    if (!isStriker && !isNonStriker) {
      return 'The dismissed batter must be the striker or the non-striker.';
    }
    if (isNonStriker && !isStriker && dismissal != DismissalType.runOut) {
      return 'Only a run-out can dismiss the non-striker.';
    }
  }
  // Rule 13
  if (d.nonStrikerId != null && d.strikerId == d.nonStrikerId) {
    return 'The striker and non-striker must be different players.';
  }
  return null;
}
