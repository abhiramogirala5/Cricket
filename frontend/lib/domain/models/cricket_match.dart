import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/enums.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// A match between two of the user's teams (API entity `MATCH`).
final class CricketMatch extends Equatable {
  const CricketMatch({
    required this.id,
    required this.teamAId,
    required this.teamBId,
    required this.createdAt,
    required this.updatedAt,
    this.matchName,
    this.locationName,
    this.scheduledAt,
    this.startedAt,
    this.completedAt,
    this.status = MatchStatus.draft,
    this.oversPerInnings = 6,
    this.localRulesProfile = defaultRulesProfile,
    this.winnerTeamId,
    this.resultSummary,
  });

  factory CricketMatch.fromJson(Map<String, Object?> json) => CricketMatch(
        id: asString(json['id']),
        teamAId: asString(json['team_a_id']),
        teamBId: asString(json['team_b_id']),
        matchName: asStringOrNull(json['match_name']),
        locationName: asStringOrNull(json['location_name']),
        scheduledAt: parseDateTimeOrNull(json['scheduled_at']),
        startedAt: parseDateTimeOrNull(json['started_at']),
        completedAt: parseDateTimeOrNull(json['completed_at']),
        status: MatchStatus.fromWire(json['status']),
        oversPerInnings: asInt(json['overs_per_innings']),
        localRulesProfile: asStringOrNull(json['local_rules_profile']) ?? defaultRulesProfile,
        winnerTeamId: asStringOrNull(json['winner_team_id']),
        resultSummary: asStringOrNull(json['result_summary']),
        createdAt: parseDateTime(json['created_at']),
        updatedAt: parseDateTime(json['updated_at']),
      );

  static const String defaultRulesProfile = 'CASUAL_GULLY';
  static const int minOvers = 1;
  static const int maxOvers = 50;

  final String id;
  final String teamAId;
  final String teamBId;
  final String? matchName;
  final String? locationName;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final MatchStatus status;
  final int oversPerInnings;
  final String localRulesProfile;
  final String? winnerTeamId;
  final String? resultSummary;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get maxLegalBalls => oversPerInnings * 6;

  bool get isFinished => status.isTerminal;

  String otherTeamId(String teamId) => teamId == teamAId ? teamBId : teamAId;

  CricketMatch copyWith({
    String? matchName,
    String? locationName,
    DateTime? startedAt,
    DateTime? completedAt,
    MatchStatus? status,
    int? oversPerInnings,
    String? winnerTeamId,
    String? resultSummary,
    DateTime? updatedAt,
  }) =>
      CricketMatch(
        id: id,
        teamAId: teamAId,
        teamBId: teamBId,
        matchName: matchName ?? this.matchName,
        locationName: locationName ?? this.locationName,
        scheduledAt: scheduledAt,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        status: status ?? this.status,
        oversPerInnings: oversPerInnings ?? this.oversPerInnings,
        localRulesProfile: localRulesProfile,
        winnerTeamId: winnerTeamId ?? this.winnerTeamId,
        resultSummary: resultSummary ?? this.resultSummary,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        ...toSyncPayload(),
        'created_at': toIsoUtc(createdAt),
        'updated_at': toIsoUtc(updatedAt),
      };

  /// Exactly the keys of API_CONTRACT §5.3 `MATCH`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'id': id,
        'team_a_id': teamAId,
        'team_b_id': teamBId,
        'match_name': matchName,
        'location_name': locationName,
        'scheduled_at': toIsoUtc(scheduledAt),
        'started_at': toIsoUtc(startedAt),
        'completed_at': toIsoUtc(completedAt),
        'status': status.wire,
        'overs_per_innings': oversPerInnings,
        'local_rules_profile': localRulesProfile,
        'winner_team_id': winnerTeamId,
        'result_summary': resultSummary,
      };

  @override
  List<Object?> get props => <Object?>[
        id,
        teamAId,
        teamBId,
        matchName,
        locationName,
        scheduledAt,
        startedAt,
        completedAt,
        status,
        oversPerInnings,
        localRulesProfile,
        winnerTeamId,
        resultSummary,
        createdAt,
        updatedAt,
      ];
}
