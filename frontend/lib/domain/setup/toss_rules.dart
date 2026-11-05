import 'package:gully_umpire/domain/models/models.dart';

/// Who wins the toss: the calling team wins when its call matches the coin.
String tossWinnerTeamId({
  required String callingTeamId,
  required String otherTeamId,
  required TossSide call,
  required TossSide result,
}) {
  return call == result ? callingTeamId : otherTeamId;
}

/// The team that bats first, given the toss. `null` when the toss has no winner or decision.
String? battingFirstTeamId(Toss toss, CricketMatch match) {
  final String? winner = toss.winnerTeamId;
  final TossDecision? decision = toss.winnerDecision;
  if (winner == null || decision == null) {
    return null;
  }
  if (winner != match.teamAId && winner != match.teamBId) {
    return null;
  }
  return decision == TossDecision.bat ? winner : match.otherTeamId(winner);
}
