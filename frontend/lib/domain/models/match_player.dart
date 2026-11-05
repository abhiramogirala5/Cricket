import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/enums.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// A player's place in one match (natural key `matchId` + `playerId`).
final class MatchPlayer extends Equatable {
  const MatchPlayer({
    required this.matchId,
    required this.playerId,
    required this.teamId,
    this.battingHand = BattingHand.unknown,
    this.declaredHeightCm,
    this.battingOrder,
    this.isCaptain = false,
    this.isWicketkeeper = false,
  });

  factory MatchPlayer.fromJson(Map<String, Object?> json) => MatchPlayer(
        matchId: asString(json['match_id']),
        playerId: asString(json['player_id']),
        teamId: asString(json['team_id']),
        battingHand: BattingHand.fromWire(json['batting_hand']),
        declaredHeightCm: asIntOrNull(json['declared_height_cm']),
        battingOrder: asIntOrNull(json['batting_order']),
        isCaptain: asBool(json['is_captain']),
        isWicketkeeper: asBool(json['is_wicketkeeper']),
      );

  final String matchId;
  final String playerId;
  final String teamId;
  final BattingHand battingHand;
  final int? declaredHeightCm;
  final int? battingOrder;
  final bool isCaptain;
  final bool isWicketkeeper;

  MatchPlayer copyWith({
    int? battingOrder,
    bool? isCaptain,
    bool? isWicketkeeper,
    BattingHand? battingHand,
    int? declaredHeightCm,
  }) =>
      MatchPlayer(
        matchId: matchId,
        playerId: playerId,
        teamId: teamId,
        battingHand: battingHand ?? this.battingHand,
        declaredHeightCm: declaredHeightCm ?? this.declaredHeightCm,
        battingOrder: battingOrder ?? this.battingOrder,
        isCaptain: isCaptain ?? this.isCaptain,
        isWicketkeeper: isWicketkeeper ?? this.isWicketkeeper,
      );

  Map<String, Object?> toJson() => toSyncPayload();

  /// Exactly the keys of API_CONTRACT §5.3 `MATCH_PLAYER`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'match_id': matchId,
        'player_id': playerId,
        'team_id': teamId,
        'batting_hand': battingHand.wire,
        'declared_height_cm': declaredHeightCm,
        'batting_order': battingOrder,
        'is_captain': isCaptain,
        'is_wicketkeeper': isWicketkeeper,
      };

  @override
  List<Object?> get props => <Object?>[
        matchId,
        playerId,
        teamId,
        battingHand,
        declaredHeightCm,
        battingOrder,
        isCaptain,
        isWicketkeeper,
      ];
}
