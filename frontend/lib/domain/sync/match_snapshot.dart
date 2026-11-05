import 'package:gully_umpire/domain/models/json_helpers.dart';
import 'package:gully_umpire/domain/models/models.dart';

/// Everything the server stores about one match (API `MatchSnapshot`, docs/API_CONTRACT.md §4.2).
final class MatchSnapshot {
  const MatchSnapshot({
    required this.match,
    required this.teams,
    required this.players,
    required this.matchPlayers,
    required this.innings,
    required this.deliveries,
    required this.decisions,
    required this.sceneScans,
    required this.wicketDetections,
    required this.trajectories,
    this.rules,
    this.toss,
  });

  factory MatchSnapshot.fromJson(Map<String, Object?> json) {
    final Map<String, Object?>? match = asJsonMapOrNull(json['match']);
    if (match == null) {
      throw const FormatException('Snapshot has no match');
    }
    List<T> list<T>(String key, T Function(Map<String, Object?> item) parse) {
      final List<Object?> raw = asJsonListOrNull(json[key]) ?? const <Object?>[];
      return raw
          .map<T>((Object? item) => parse(asJsonMapOrNull(item) ?? <String, Object?>{}))
          .toList(growable: false);
    }

    final Map<String, Object?>? rules = asJsonMapOrNull(json['rules']);
    final Map<String, Object?>? toss = asJsonMapOrNull(json['toss']);
    return MatchSnapshot(
      match: CricketMatch.fromJson(match),
      rules: rules == null ? null : MatchRules.fromJson(rules),
      teams: list<Team>('teams', Team.fromJson),
      players: list<Player>('players', Player.fromJson),
      matchPlayers: list<MatchPlayer>('match_players', MatchPlayer.fromJson),
      toss: toss == null ? null : Toss.fromJson(toss),
      innings: list<Innings>('innings', Innings.fromJson),
      deliveries: list<Delivery>('deliveries', Delivery.fromJson),
      decisions: list<DecisionRecord>('delivery_decisions', DecisionRecord.fromJson),
      sceneScans: list<SceneScan>('scene_scans', SceneScan.fromJson),
      wicketDetections: list<WicketDetection>('wicket_detections', WicketDetection.fromJson),
      trajectories: list<TrajectorySnapshot>('trajectory_snapshots', TrajectorySnapshot.fromJson),
    );
  }

  final CricketMatch match;
  final MatchRules? rules;
  final List<Team> teams;
  final List<Player> players;
  final List<MatchPlayer> matchPlayers;
  final Toss? toss;
  final List<Innings> innings;
  final List<Delivery> deliveries;
  final List<DecisionRecord> decisions;
  final List<SceneScan> sceneScans;
  final List<WicketDetection> wicketDetections;
  final List<TrajectorySnapshot> trajectories;
}
