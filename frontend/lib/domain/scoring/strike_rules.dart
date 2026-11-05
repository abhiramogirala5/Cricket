import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/delivery.dart';
import 'package:gully_umpire/domain/models/enums.dart';
import 'package:gully_umpire/domain/scoring/delivery_rules.dart';
import 'package:gully_umpire/domain/scoring/score_engine.dart';

/// The two ends a batter can stand at.
enum BatterSlot { striker, nonStriker }

/// Runs physically run on a ball (docs/SCORING_RULES.md §8).
///
/// A boundary (4 or 6 off the bat) is not run. Everything else off the bat counts (so 5 and 7
/// are overthrow runs that were run), plus the extras that were run beyond the penalty run.
int runsRun({
  required int runsBat,
  required int runsExtras,
  required bool isWide,
  required bool isNoBall,
}) {
  final int fromBat = (runsBat == 4 || runsBat == 6) ? 0 : runsBat;
  final int penalty = (isWide || isNoBall) ? 1 : 0;
  final int fromExtras = runsExtras - penalty;
  return fromBat + (fromExtras > 0 ? fromExtras : 0);
}

/// [runsRun] for a stored delivery.
int deliveryRunsRun(Delivery delivery) => runsRun(
      runsBat: delivery.runsBat,
      runsExtras: delivery.runsExtras,
      isWide: delivery.isWide,
      isNoBall: delivery.isNoBall,
    );

/// Who is at the crease for the next ball, derived from what just happened.
///
/// A `null` end means a batter is still missing (a wicket fell) and the scorer must pick the
/// incoming batter ([needsNewBatter]).
final class NextBallSetup extends Equatable {
  const NextBallSetup({
    required this.strikerId,
    required this.nonStrikerId,
    this.overCompleted = false,
    this.vacantSlot,
    this.strikeChoiceAllowed = false,
  });

  final String? strikerId;
  final String? nonStrikerId;

  /// The ball just bowled was the 6th legal ball: a new bowler is needed.
  final bool overCompleted;

  /// The end the incoming batter takes, or `null` when both ends are filled.
  final BatterSlot? vacantSlot;

  /// After a run-out the scorer may override who faces the next ball.
  final bool strikeChoiceAllowed;

  bool get needsNewBatter => vacantSlot != null;

  bool get isComplete => strikerId != null;

  /// Fills the vacant end with [playerId]; returns `this` when no end is vacant.
  NextBallSetup withIncoming(String playerId) {
    switch (vacantSlot) {
      case BatterSlot.striker:
        return NextBallSetup(
          strikerId: playerId,
          nonStrikerId: nonStrikerId,
          overCompleted: overCompleted,
          strikeChoiceAllowed: strikeChoiceAllowed,
        );
      case BatterSlot.nonStriker:
        return NextBallSetup(
          strikerId: strikerId,
          nonStrikerId: playerId,
          overCompleted: overCompleted,
          strikeChoiceAllowed: strikeChoiceAllowed,
        );
      case null:
        return this;
    }
  }

  /// The two batters exchange ends. A single batter stays where they are.
  NextBallSetup swapped() {
    if (nonStrikerId == null || strikerId == null) {
      return this;
    }
    return NextBallSetup(
      strikerId: nonStrikerId,
      nonStrikerId: strikerId,
      overCompleted: overCompleted,
      vacantSlot: vacantSlot,
      strikeChoiceAllowed: strikeChoiceAllowed,
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[strikerId, nonStrikerId, overCompleted, vacantSlot, strikeChoiceAllowed];
}

/// Batters and over-end state after [delivery] (docs/SCORING_RULES.md §8).
///
/// * No wicket: the batters swap if an odd number of runs was run.
/// * Wicket: the incoming batter takes the dismissed batter's end and the run parity is ignored.
///   After a run-out the scorer may still choose who faces the next ball.
/// * After the 6th legal ball the batters swap once more and a new bowler is needed.
NextBallSetup setupAfterDelivery(Delivery delivery) {
  final bool overCompleted =
      delivery.isLegal && delivery.legalBallNumber == ballsPerOver;

  String? striker = delivery.strikerId;
  String? nonStriker = delivery.nonStrikerId;
  bool strikeChoiceAllowed = false;
  bool slotWasVacated = false;

  if (delivery.isWicket) {
    final String? dismissedId = delivery.dismissedPlayerId;
    if (dismissedId != null && dismissedId == striker) {
      striker = null;
      slotWasVacated = true;
    } else if (dismissedId != null && dismissedId == nonStriker) {
      nonStriker = null;
      slotWasVacated = true;
    }
    strikeChoiceAllowed = delivery.dismissalType == DismissalType.runOut;
  } else if (deliveryRunsRun(delivery).isOdd) {
    final previousStriker = striker;
    striker = nonStriker;
    nonStriker = previousStriker;
  }

  if (overCompleted) {
    final String? previousStriker = striker;
    striker = nonStriker;
    nonStriker = previousStriker;
  }

  BatterSlot? vacantSlot;
  if (slotWasVacated) {
    if (striker == null) {
      vacantSlot = BatterSlot.striker;
    } else if (nonStriker == null) {
      vacantSlot = BatterSlot.nonStriker;
    }
  }

  return NextBallSetup(
    strikerId: striker,
    nonStrikerId: nonStriker,
    overCompleted: overCompleted,
    vacantSlot: vacantSlot,
    strikeChoiceAllowed: strikeChoiceAllowed,
  );
}

/// The batting pair for the next ball of an innings, or `null` when no ball was bowled yet
/// (the scorer picks the openers).
///
/// If the most recent ball was undone, its own pair is used again, so an incoming batter who
/// had already been chosen for it is not lost.
NextBallSetup? currentSetup(List<Delivery> deliveries) {
  final Delivery? latest = ScoreEngine.latest(deliveries);
  if (latest == null) {
    return null;
  }
  if (latest.isVoided) {
    return NextBallSetup(strikerId: latest.strikerId, nonStrikerId: latest.nonStrikerId);
  }
  return setupAfterDelivery(latest);
}

/// Batting-team players who have not batted yet and are not at the crease, in batting order.
List<String> availableBatters({
  required List<String> battingOrder,
  required List<Delivery> deliveries,
  Iterable<String> atCrease = const <String>[],
}) {
  final Set<String> used = <String>{...atCrease};
  for (final Delivery delivery in deliveries) {
    if (delivery.isVoided) {
      continue;
    }
    used.add(delivery.strikerId);
    final String? nonStrikerId = delivery.nonStrikerId;
    if (nonStrikerId != null) {
      used.add(nonStrikerId);
    }
    final String? dismissedId = delivery.dismissedPlayerId;
    if (dismissedId != null) {
      used.add(dismissedId);
    }
  }
  return battingOrder.where((String id) => !used.contains(id)).toList(growable: false);
}
