import 'package:gully_umpire/domain/models/models.dart';

/// What kind of ball it was, as far as the over count goes.
enum BallLegality { legal, wide, noBall }

/// What the runs of a ball were: off the bat, byes or leg-byes.
enum RunsMode { bat, bye, legBye }

/// Builds the ball the scorer described, exactly as `ScoreEngine` wants it.
///
/// * [runs] is the number of runs that were run (or the boundary value), NOT counting the
///   one-run penalty of a wide or a no-ball.
/// * On a wide every run is a wide, so [runsMode] is ignored there.
/// * On a no-ball the runs can still come off the bat, or be byes or leg-byes.
/// * A [dismissal] makes it a wicket; [dismissedPlayerId] defaults to the striker.
DeliveryDraft buildDraft({
  required String bowlerId,
  required String strikerId,
  String? nonStrikerId,
  BallLegality kind = BallLegality.legal,
  int runs = 0,
  RunsMode runsMode = RunsMode.bat,
  DismissalType? dismissal,
  String? dismissedPlayerId,
}) {
  final bool wide = kind == BallLegality.wide;
  final bool noBall = kind == BallLegality.noBall;
  final int penalty = noBall ? 1 : 0;

  int runsBat = 0;
  int runsExtras = 0;
  bool isBye = false;
  bool isLegBye = false;

  if (wide) {
    runsExtras = 1 + runs;
  } else {
    switch (runsMode) {
      case RunsMode.bat:
        runsBat = runs;
        runsExtras = penalty;
      case RunsMode.bye:
        isBye = true;
        runsExtras = penalty + runs;
      case RunsMode.legBye:
        isLegBye = true;
        runsExtras = penalty + runs;
    }
  }

  return DeliveryDraft(
    bowlerId: bowlerId,
    strikerId: strikerId,
    nonStrikerId: nonStrikerId,
    runsBat: runsBat,
    runsExtras: runsExtras,
    isWide: wide,
    isNoBall: noBall,
    isBye: isBye,
    isLegBye: isLegBye,
    isWicket: dismissal != null,
    dismissalType: dismissal,
    dismissedPlayerId: dismissal == null ? null : (dismissedPlayerId ?? strikerId),
  );
}

/// The ways a batter can be out on a ball of this [kind] (SCORING_RULES.md §2, rules 11 and 12).
List<DismissalType> allowedDismissals(BallLegality kind) {
  switch (kind) {
    case BallLegality.legal:
      return DismissalType.values;
    case BallLegality.wide:
      return const <DismissalType>[
        DismissalType.runOut,
        DismissalType.stumped,
        DismissalType.hitWicket,
      ];
    case BallLegality.noBall:
      return const <DismissalType>[DismissalType.runOut];
  }
}

/// Only a run-out can dismiss the batter at the other end.
bool nonStrikerCanBeOut(DismissalType dismissal) => dismissal == DismissalType.runOut;
