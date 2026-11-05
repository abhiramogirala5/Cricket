import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/toss_rules.dart';

/// The next thing that has to happen in a match.
enum MatchStepKind {
  /// Let the assistant look for the wicket.
  scan,
  toss,
  startFirstInnings,
  startSecondInnings,

  /// An innings is open: score the balls.
  score,

  /// Both innings are over: work out the result.
  finish,

  /// The match is over: look at the scorecard.
  scorecard,
}

/// What the big button on the match page does, and what it says.
final class MatchStep extends Equatable {
  const MatchStep({
    required this.kind,
    required this.label,
    required this.hint,
    this.battingTeamId,
  });

  final MatchStepKind kind;
  final String label;
  final String hint;

  /// Only for the two "start innings" steps.
  final String? battingTeamId;

  @override
  List<Object?> get props => <Object?>[kind, label, hint, battingTeamId];
}

/// Works out the next step of a match from what has been saved so far.
///
/// [scanAvailable] says whether the app can look for the wicket at all in this build. The scan
/// is only suggested until the toss, and only if it has not been done yet. With the live camera
/// ([markByHand]) the "scan" is the umpire marking the stumps on the camera picture, and the
/// words say so.
MatchStep nextMatchStep(
  MatchBundle bundle, {
  required bool scanAvailable,
  bool markByHand = false,
}) {
  final CricketMatch match = bundle.match;
  if (match.isFinished) {
    return const MatchStep(
      kind: MatchStepKind.scorecard,
      label: 'View scorecard',
      hint: 'The match is over.',
    );
  }

  if (bundle.innings.isEmpty) {
    final Toss? toss = bundle.toss;
    if (toss == null) {
      final bool scanned = bundle.activeWicket != null || bundle.latestScan != null;
      if (scanAvailable && !scanned) {
        if (markByHand) {
          return const MatchStep(
            kind: MatchStepKind.scan,
            label: 'Mark the stumps',
            hint: 'Show the camera where the stumps are, or skip it and score by hand.',
          );
        }
        return const MatchStep(
          kind: MatchStepKind.scan,
          label: 'Scan the pitch',
          hint: 'Let the assistant find the wicket, or skip it and score by hand.',
        );
      }
      return const MatchStep(
        kind: MatchStepKind.toss,
        label: 'Do the toss',
        hint: 'Find out who bats first.',
      );
    }
    final String? batting = battingFirstTeamId(toss, match);
    if (batting == null) {
      return const MatchStep(
        kind: MatchStepKind.toss,
        label: 'Do the toss',
        hint: 'The toss needs a winner and a choice to bat or bowl.',
      );
    }
    return MatchStep(
      kind: MatchStepKind.startFirstInnings,
      label: 'Start first innings',
      hint: '${bundle.teamName(batting)} bat first.',
      battingTeamId: batting,
    );
  }

  final Innings last = bundle.innings.last;
  if (!last.isClosed) {
    final bool started = bundle.deliveriesOf(last.id).any((Delivery d) => !d.isVoided);
    return MatchStep(
      kind: MatchStepKind.score,
      label: started ? 'Continue scoring' : 'Start scoring',
      hint: '${bundle.teamName(last.battingTeamId)} are batting.',
    );
  }
  if (bundle.innings.length < 2) {
    final String batting = match.otherTeamId(last.battingTeamId);
    return MatchStep(
      kind: MatchStepKind.startSecondInnings,
      label: 'Start second innings',
      hint: '${bundle.teamName(batting)} chase ${last.totalRuns + 1} to win.',
      battingTeamId: batting,
    );
  }
  return const MatchStep(
    kind: MatchStepKind.finish,
    label: 'Finish the match',
    hint: 'Both innings are done. Work out the result.',
  );
}
