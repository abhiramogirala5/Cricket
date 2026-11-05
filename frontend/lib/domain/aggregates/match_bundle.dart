import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/models.dart';

/// Everything the app knows about one match, assembled from the local database.
///
/// This is a read model: it is rebuilt after every change and never mutated. Ball paths
/// ([TrajectorySnapshot]) are not part of it because they are large; they are loaded one
/// delivery at a time.
final class MatchBundle extends Equatable {
  const MatchBundle({
    required this.match,
    required this.teamA,
    required this.teamB,
    required this.matchPlayers,
    required this.players,
    required this.innings,
    required this.deliveriesByInnings,
    this.rules,
    this.toss,
    this.decisions = const <DecisionRecord>[],
    this.sceneScans = const <SceneScan>[],
    this.wicketDetections = const <WicketDetection>[],
  });

  final CricketMatch match;
  final Team teamA;
  final Team teamB;
  final MatchRules? rules;
  final List<MatchPlayer> matchPlayers;

  /// Roster entries of the players in this match, by id.
  final Map<String, Player> players;
  final Toss? toss;

  /// Ordered by innings number.
  final List<Innings> innings;

  /// Every delivery (voided ones included) per innings id, ordered by sequence.
  final Map<String, List<Delivery>> deliveriesByInnings;
  final List<DecisionRecord> decisions;
  final List<SceneScan> sceneScans;
  final List<WicketDetection> wicketDetections;

  /// The rules of this match, or the defaults when none were stored.
  MatchRules get effectiveRules => rules ?? MatchRules(matchId: match.id);

  Team teamById(String teamId) => teamId == teamA.id ? teamA : teamB;

  String teamName(String teamId) {
    if (teamId == teamA.id) {
      return teamA.name;
    }
    if (teamId == teamB.id) {
      return teamB.name;
    }
    return 'Team';
  }

  Map<String, String> get teamNames =>
      <String, String>{teamA.id: teamA.name, teamB.id: teamB.name};

  /// The squad of [teamId] in batting order (players without an order come last, by name).
  List<MatchPlayer> squad(String teamId) {
    final List<MatchPlayer> members =
        matchPlayers.where((MatchPlayer mp) => mp.teamId == teamId).toList();
    members.sort((MatchPlayer a, MatchPlayer b) {
      final int orderA = a.battingOrder ?? 1 << 30;
      final int orderB = b.battingOrder ?? 1 << 30;
      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }
      return playerName(a.playerId).toLowerCase().compareTo(playerName(b.playerId).toLowerCase());
    });
    return members;
  }

  /// Player ids of [teamId] in batting order.
  List<String> battingOrderIds(String teamId) =>
      squad(teamId).map<String>((MatchPlayer mp) => mp.playerId).toList(growable: false);

  Set<String> get matchPlayerIds =>
      matchPlayers.map<String>((MatchPlayer mp) => mp.playerId).toSet();

  Player? playerById(String playerId) => players[playerId];

  String playerName(String playerId) => players[playerId]?.displayName ?? 'Unknown player';

  MatchPlayer? matchPlayerById(String playerId) {
    for (final MatchPlayer mp in matchPlayers) {
      if (mp.playerId == playerId) {
        return mp;
      }
    }
    return null;
  }

  Innings? inningsByNumber(int number) {
    for (final Innings item in innings) {
      if (item.inningsNumber == number) {
        return item;
      }
    }
    return null;
  }

  Innings? inningsById(String inningsId) {
    for (final Innings item in innings) {
      if (item.id == inningsId) {
        return item;
      }
    }
    return null;
  }

  /// The innings with the highest number, or `null` before the first one starts.
  Innings? get currentInnings => innings.isEmpty ? null : innings.last;

  List<Delivery> deliveriesOf(String inningsId) =>
      deliveriesByInnings[inningsId] ?? const <Delivery>[];

  List<DecisionRecord> decisionsOf(String deliveryId) => decisions
      .where((DecisionRecord decision) => decision.deliveryId == deliveryId)
      .toList(growable: false);

  /// The wicket found by the scan that is currently in use.
  WicketDetection? get activeWicket {
    WicketDetection? best;
    for (final WicketDetection detection in wicketDetections) {
      if (!detection.isActive) {
        continue;
      }
      if (best == null || detection.detectedAt.isAfter(best.detectedAt)) {
        best = detection;
      }
    }
    return best;
  }

  SceneScan? get latestScan {
    SceneScan? best;
    for (final SceneScan scan in sceneScans) {
      if (best == null || scan.createdAt.isAfter(best.createdAt)) {
        best = scan;
      }
    }
    return best;
  }

  /// Runs scored in the first innings, or `null` if it has not started.
  int? get firstInningsTotal => inningsByNumber(1)?.totalRuns;

  @override
  List<Object?> get props => <Object?>[
        match,
        teamA,
        teamB,
        rules,
        matchPlayers,
        players,
        toss,
        innings,
        deliveriesByInnings,
        decisions,
        sceneScans,
        wicketDetections,
      ];
}
