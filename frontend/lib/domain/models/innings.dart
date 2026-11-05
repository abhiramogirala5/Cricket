import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// One innings of a match (API entity `INNINGS`). Totals are derived from deliveries.
final class Innings extends Equatable {
  const Innings({
    required this.id,
    required this.matchId,
    required this.inningsNumber,
    required this.battingTeamId,
    required this.bowlingTeamId,
    required this.startedAt,
    this.totalRuns = 0,
    this.wickets = 0,
    this.legalBalls = 0,
    this.endedAt,
  });

  factory Innings.fromJson(Map<String, Object?> json) => Innings(
        id: asString(json['id']),
        matchId: asString(json['match_id']),
        inningsNumber: asInt(json['innings_number']),
        battingTeamId: asString(json['batting_team_id']),
        bowlingTeamId: asString(json['bowling_team_id']),
        totalRuns: asInt(json['total_runs'] ?? 0),
        wickets: asInt(json['wickets'] ?? 0),
        legalBalls: asInt(json['legal_balls'] ?? 0),
        startedAt: parseDateTime(json['started_at']),
        endedAt: parseDateTimeOrNull(json['ended_at']),
      );

  final String id;
  final String matchId;
  final int inningsNumber;
  final String battingTeamId;
  final String bowlingTeamId;
  final int totalRuns;
  final int wickets;
  final int legalBalls;
  final DateTime startedAt;
  final DateTime? endedAt;

  bool get isClosed => endedAt != null;

  Innings copyWith({int? totalRuns, int? wickets, int? legalBalls, DateTime? endedAt}) => Innings(
        id: id,
        matchId: matchId,
        inningsNumber: inningsNumber,
        battingTeamId: battingTeamId,
        bowlingTeamId: bowlingTeamId,
        totalRuns: totalRuns ?? this.totalRuns,
        wickets: wickets ?? this.wickets,
        legalBalls: legalBalls ?? this.legalBalls,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        ...toSyncPayload(),
        'total_runs': totalRuns,
        'wickets': wickets,
        'legal_balls': legalBalls,
      };

  /// Exactly the keys of API_CONTRACT §5.3 `INNINGS` (the server computes the totals).
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'id': id,
        'match_id': matchId,
        'innings_number': inningsNumber,
        'batting_team_id': battingTeamId,
        'bowling_team_id': bowlingTeamId,
        'started_at': toIsoUtc(startedAt),
        'ended_at': toIsoUtc(endedAt),
      };

  @override
  List<Object?> get props => <Object?>[
        id,
        matchId,
        inningsNumber,
        battingTeamId,
        bowlingTeamId,
        totalRuns,
        wickets,
        legalBalls,
        startedAt,
        endedAt,
      ];
}
