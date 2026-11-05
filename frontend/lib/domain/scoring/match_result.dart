import 'package:equatable/equatable.dart';
import 'package:gully_umpire/core/utils/formatters.dart';

/// Outcome of a finished two-innings match (docs/SCORING_RULES.md §8).
final class MatchResult extends Equatable {
  const MatchResult({required this.winnerTeamId, required this.summary});

  /// `null` for a tie.
  final String? winnerTeamId;

  /// One line for the scorecard and the match list, e.g. `Gully Kings won by 12 runs`.
  final String summary;

  bool get isTie => winnerTeamId == null;

  @override
  List<Object?> get props => <Object?>[winnerTeamId, summary];
}

/// Runs the chasing team needs to win (one more than the first innings total).
int chaseTarget(int firstInningsTotal) => firstInningsTotal + 1;

/// Works out who won.
///
/// * Chasing total above the first total: the chasing team wins by the wickets it has in hand
///   (`chasingPlayerCount - 1 - chasingWickets`).
/// * First total above the chasing total: the first team wins by the run difference.
/// * Equal totals: tie.
///
/// [teamNames] maps team ids to display names; a missing name falls back to "Team".
MatchResult computeMatchResult({
  required String firstTeamId,
  required String secondTeamId,
  required int firstTotal,
  required int secondTotal,
  required int secondWickets,
  required int secondPlayerCount,
  required Map<String, String> teamNames,
}) {
  String nameOf(String teamId) => teamNames[teamId] ?? 'Team';

  if (secondTotal > firstTotal) {
    final int wicketsInHand = secondPlayerCount - 1 - secondWickets;
    final int margin = wicketsInHand < 1 ? 1 : wicketsInHand;
    return MatchResult(
      winnerTeamId: secondTeamId,
      summary: '${nameOf(secondTeamId)} won by ${pluralize(margin, 'wicket')}',
    );
  }
  if (firstTotal > secondTotal) {
    return MatchResult(
      winnerTeamId: firstTeamId,
      summary: '${nameOf(firstTeamId)} won by ${pluralize(firstTotal - secondTotal, 'run')}',
    );
  }
  return const MatchResult(winnerTeamId: null, summary: 'Match tied');
}
