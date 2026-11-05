import 'package:gully_umpire/domain/models/models.dart';

/// Limits that the server enforces too (docs/API_CONTRACT.md §5.3). Forms use the same numbers.
abstract final class MatchSetupLimits {
  static const int minPlayersPerTeam = 2;
  static const int maxPlayersPerTeam = 30;
  static const int maxNameLength = 100;
  static const int maxMatchNameLength = 150;
  static const int maxLocationLength = 255;
  static const int minHeightCm = 100;
  static const int maxHeightCm = 230;
}

/// A refused setup (the message is safe to show to the user).
final class SetupException implements Exception {
  const SetupException(this.message);

  final String message;

  @override
  String toString() => 'SetupException: $message';
}

/// One player on a team sheet.
final class RosterEntryInput {
  const RosterEntryInput({
    required this.displayName,
    this.existingPlayerId,
    this.battingHand = BattingHand.unknown,
    this.declaredHeightCm,
    this.isCaptain = false,
    this.isWicketkeeper = false,
  });

  final String displayName;

  /// Set when the player was picked from the saved roster.
  final String? existingPlayerId;
  final BattingHand battingHand;
  final int? declaredHeightCm;
  final bool isCaptain;
  final bool isWicketkeeper;

  String get trimmedName => displayName.trim();
}

/// A team sheet: a team name and its players in batting order.
final class TeamInput {
  const TeamInput({required this.name, required this.players});

  final String name;
  final List<RosterEntryInput> players;

  String get trimmedName => name.trim();
}

/// Everything entered on the "new match" form.
final class NewMatchInput {
  const NewMatchInput({
    required this.teamA,
    required this.teamB,
    this.matchName,
    this.locationName,
    this.oversPerInnings = 6,
    this.rules,
  });

  final TeamInput teamA;
  final TeamInput teamB;
  final String? matchName;
  final String? locationName;
  final int oversPerInnings;

  /// The umpiring rules for this match; the defaults when `null`. The `matchId` is replaced.
  final MatchRules? rules;
}

/// Checks a team sheet and returns the first problem in plain language, or `null` when it is fine.
String? validateTeamInput(TeamInput team, {required String label}) {
  final String name = team.trimmedName;
  if (name.isEmpty) {
    return 'Enter a name for $label.';
  }
  if (name.length > MatchSetupLimits.maxNameLength) {
    return 'The name of $label is too long.';
  }
  if (team.players.length < MatchSetupLimits.minPlayersPerTeam) {
    return '$name needs at least ${MatchSetupLimits.minPlayersPerTeam} players.';
  }
  if (team.players.length > MatchSetupLimits.maxPlayersPerTeam) {
    return '$name can have at most ${MatchSetupLimits.maxPlayersPerTeam} players.';
  }
  int captains = 0;
  int keepers = 0;
  for (final RosterEntryInput player in team.players) {
    final String playerName = player.trimmedName;
    if (playerName.isEmpty) {
      return 'Every player in $name needs a name.';
    }
    if (playerName.length > MatchSetupLimits.maxNameLength) {
      return 'A player name in $name is too long.';
    }
    final int? height = player.declaredHeightCm;
    if (height != null &&
        (height < MatchSetupLimits.minHeightCm || height > MatchSetupLimits.maxHeightCm)) {
      return 'Height must be between ${MatchSetupLimits.minHeightCm} and '
          '${MatchSetupLimits.maxHeightCm} cm ($playerName).';
    }
    if (player.isCaptain) {
      captains += 1;
    }
    if (player.isWicketkeeper) {
      keepers += 1;
    }
  }
  if (captains > 1) {
    return '$name can only have one captain.';
  }
  if (keepers > 1) {
    return '$name can only have one wicketkeeper.';
  }
  return null;
}

/// Checks the whole "new match" form. Returns the first problem, or `null` when it is fine.
String? validateNewMatch(NewMatchInput input) {
  final String? teamAProblem = validateTeamInput(input.teamA, label: 'team 1');
  if (teamAProblem != null) {
    return teamAProblem;
  }
  final String? teamBProblem = validateTeamInput(input.teamB, label: 'team 2');
  if (teamBProblem != null) {
    return teamBProblem;
  }
  if (input.teamA.trimmedName.toLowerCase() == input.teamB.trimmedName.toLowerCase()) {
    return 'The two teams need different names.';
  }
  final Set<String> savedIds = <String>{};
  for (final RosterEntryInput player in <RosterEntryInput>[
    ...input.teamA.players,
    ...input.teamB.players,
  ]) {
    final String? id = player.existingPlayerId;
    if (id != null && !savedIds.add(id)) {
      return '${player.trimmedName} is listed more than once.';
    }
  }
  if (input.oversPerInnings < CricketMatch.minOvers || input.oversPerInnings > CricketMatch.maxOvers) {
    return 'Overs per innings must be between ${CricketMatch.minOvers} and ${CricketMatch.maxOvers}.';
  }
  final String? matchName = input.matchName?.trim();
  if (matchName != null && matchName.length > MatchSetupLimits.maxMatchNameLength) {
    return 'The match name is too long.';
  }
  final String? location = input.locationName?.trim();
  if (location != null && location.length > MatchSetupLimits.maxLocationLength) {
    return 'The place name is too long.';
  }
  final MatchRules? rules = input.rules;
  if (rules != null) {
    if (rules.lateralReachMultiplier < MatchRules.minLateralReach ||
        rules.lateralReachMultiplier > MatchRules.maxLateralReach) {
      return 'The wide width setting is out of range.';
    }
    final int? bouncers = rules.maxBouncersPerOver;
    if (bouncers != null && (bouncers < 0 || bouncers > 6)) {
      return 'Bouncers per over must be between 0 and 6.';
    }
  }
  return null;
}

/// Checks a single player (roster screen).
String? validatePlayerFields({required String name, int? heightCm}) {
  final String trimmed = name.trim();
  if (trimmed.isEmpty) {
    return 'Enter a name.';
  }
  if (trimmed.length > MatchSetupLimits.maxNameLength) {
    return 'The name is too long.';
  }
  if (heightCm != null &&
      (heightCm < MatchSetupLimits.minHeightCm || heightCm > MatchSetupLimits.maxHeightCm)) {
    return 'Height must be between ${MatchSetupLimits.minHeightCm} and '
        '${MatchSetupLimits.maxHeightCm} cm.';
  }
  return null;
}
