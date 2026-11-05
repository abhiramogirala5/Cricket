import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/enums.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// The coin toss (API entity `TOSS`, one per match).
final class Toss extends Equatable {
  const Toss({
    required this.id,
    required this.matchId,
    required this.callChoice,
    required this.result,
    required this.createdAt,
    this.calledByPlayerId,
    this.winnerTeamId,
    this.winnerDecision,
  });

  factory Toss.fromJson(Map<String, Object?> json) => Toss(
        id: asString(json['id']),
        matchId: asString(json['match_id']),
        calledByPlayerId: asStringOrNull(json['called_by_player_id']),
        callChoice: TossSide.fromWire(json['call_choice']),
        result: TossSide.fromWire(json['result']),
        winnerTeamId: asStringOrNull(json['winner_team_id']),
        winnerDecision: TossDecision.fromWireOrNull(json['winner_decision']),
        createdAt: parseDateTime(json['created_at']),
      );

  final String id;
  final String matchId;
  final String? calledByPlayerId;
  final TossSide callChoice;
  final TossSide result;
  final String? winnerTeamId;
  final TossDecision? winnerDecision;
  final DateTime createdAt;

  /// True when the caller guessed the coin correctly.
  bool get callerWon => callChoice == result;

  Toss copyWith({String? winnerTeamId, TossDecision? winnerDecision}) => Toss(
        id: id,
        matchId: matchId,
        calledByPlayerId: calledByPlayerId,
        callChoice: callChoice,
        result: result,
        winnerTeamId: winnerTeamId ?? this.winnerTeamId,
        winnerDecision: winnerDecision ?? this.winnerDecision,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        ...toSyncPayload(),
        'created_at': toIsoUtc(createdAt),
      };

  /// Exactly the keys of API_CONTRACT §5.3 `TOSS`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'id': id,
        'match_id': matchId,
        'called_by_player_id': calledByPlayerId,
        'call_choice': callChoice.wire,
        'result': result.wire,
        'winner_team_id': winnerTeamId,
        'winner_decision': winnerDecision?.wire,
      };

  @override
  List<Object?> get props => <Object?>[
        id,
        matchId,
        calledByPlayerId,
        callChoice,
        result,
        winnerTeamId,
        winnerDecision,
        createdAt,
      ];
}
