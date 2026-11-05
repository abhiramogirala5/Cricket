import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';

import 'scoring_fixtures.dart';

final DateTime _t0 = DateTime.utc(2026, 10, 8, 7, 33);

/// Team A bats (players `a1`, `a2`, ... named `A1`, `A2`, ...), team B bowls (`b1`, ... `B1`, ...).
/// Ids match `makeInnings` / `makeDelivery`: match `match-1`, teams `team-a` and `team-b`.
MatchBundle makeBundle({
  List<Innings>? innings,
  Map<String, List<Delivery>> deliveriesByInnings = const <String, List<Delivery>>{},
  int teamASize = 4,
  int teamBSize = 4,
  int overs = 2,
  MatchStatus status = MatchStatus.live,
  Toss? toss,
  MatchRules? rules,
  List<SceneScan> sceneScans = const <SceneScan>[],
  List<WicketDetection> wicketDetections = const <WicketDetection>[],
  List<DecisionRecord> decisions = const <DecisionRecord>[],
}) {
  final CricketMatch match = CricketMatch(
    id: matchId,
    teamAId: 'team-a',
    teamBId: 'team-b',
    status: status,
    oversPerInnings: overs,
    createdAt: _t0,
    updatedAt: _t0,
  );
  final List<MatchPlayer> matchPlayers = <MatchPlayer>[
    for (int i = 1; i <= teamASize; i++)
      MatchPlayer(matchId: matchId, playerId: 'a$i', teamId: 'team-a', battingOrder: i),
    for (int i = 1; i <= teamBSize; i++)
      MatchPlayer(matchId: matchId, playerId: 'b$i', teamId: 'team-b', battingOrder: i),
  ];
  final Map<String, Player> players = <String, Player>{
    for (final MatchPlayer member in matchPlayers)
      member.playerId: Player(
        id: member.playerId,
        displayName: member.playerId.toUpperCase(),
        createdAt: _t0,
        updatedAt: _t0,
      ),
  };
  return MatchBundle(
    match: match,
    teamA: Team(id: 'team-a', name: 'Reds', createdAt: _t0, updatedAt: _t0),
    teamB: Team(id: 'team-b', name: 'Blues', createdAt: _t0, updatedAt: _t0),
    rules: rules,
    toss: toss,
    matchPlayers: matchPlayers,
    players: players,
    innings: innings ?? <Innings>[makeInnings()],
    deliveriesByInnings: deliveriesByInnings,
    sceneScans: sceneScans,
    wicketDetections: wicketDetections,
    decisions: decisions,
  );
}

/// The second innings of [makeBundle]: team B bats.
Innings makeSecondInnings({DateTime? endedAt}) => Innings(
      id: 'innings-2',
      matchId: matchId,
      inningsNumber: 2,
      battingTeamId: 'team-b',
      bowlingTeamId: 'team-a',
      startedAt: _t0,
      endedAt: endedAt,
    );
