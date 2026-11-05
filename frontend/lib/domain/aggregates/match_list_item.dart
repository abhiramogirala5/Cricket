import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/models.dart';

/// One row of the match list: the match, its team names and its innings scores.
final class MatchListItem extends Equatable {
  const MatchListItem({
    required this.match,
    required this.teamAName,
    required this.teamBName,
    required this.innings,
  });

  final CricketMatch match;
  final String teamAName;
  final String teamBName;

  /// Ordered by innings number.
  final List<Innings> innings;

  String get title {
    final String? name = match.matchName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return '$teamAName vs $teamBName';
  }

  String teamName(String teamId) => teamId == match.teamAId ? teamAName : teamBName;

  /// Whether the match can still be scored.
  bool get isOpen => !match.isFinished;

  @override
  List<Object?> get props => <Object?>[match, teamAName, teamBName, innings];
}
