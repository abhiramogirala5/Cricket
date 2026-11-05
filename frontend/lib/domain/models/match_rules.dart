import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// Per-match umpiring rules (API entity `MATCH_RULES`, natural key `matchId`).
final class MatchRules extends Equatable {
  const MatchRules({
    required this.matchId,
    this.wideEnabled = true,
    this.noBallEnabled = true,
    this.frontFootNoBallEnabled = false,
    this.edgeReviewEnabled = true,
    this.lbwReviewEnabled = true,
    this.fullTossAboveWaistIsNoBall = true,
    this.bouncedAboveShoulderIsNoBall = false,
    this.maxBouncersPerOver,
    this.lateralReachMultiplier = defaultLateralReach,
  });

  factory MatchRules.fromJson(Map<String, Object?> json) => MatchRules(
        matchId: asString(json['match_id']),
        wideEnabled: asBool(json['wide_enabled'], fallback: true),
        noBallEnabled: asBool(json['no_ball_enabled'], fallback: true),
        frontFootNoBallEnabled: asBool(json['front_foot_no_ball_enabled']),
        edgeReviewEnabled: asBool(json['edge_review_enabled'], fallback: true),
        lbwReviewEnabled: asBool(json['lbw_review_enabled'], fallback: true),
        fullTossAboveWaistIsNoBall: asBool(json['full_toss_above_waist_is_no_ball'], fallback: true),
        bouncedAboveShoulderIsNoBall: asBool(json['bounced_above_shoulder_is_no_ball']),
        maxBouncersPerOver: asIntOrNull(json['max_bouncers_per_over']),
        lateralReachMultiplier:
            asDoubleOrNull(json['lateral_reach_multiplier']) ?? defaultLateralReach,
      );

  static const double defaultLateralReach = 0.60;
  static const double minLateralReach = 0.20;
  static const double maxLateralReach = 1.50;

  final String matchId;
  final bool wideEnabled;
  final bool noBallEnabled;
  final bool frontFootNoBallEnabled;
  final bool edgeReviewEnabled;
  final bool lbwReviewEnabled;
  final bool fullTossAboveWaistIsNoBall;
  final bool bouncedAboveShoulderIsNoBall;
  final int? maxBouncersPerOver;
  final double lateralReachMultiplier;

  MatchRules copyWith({
    bool? wideEnabled,
    bool? noBallEnabled,
    bool? frontFootNoBallEnabled,
    bool? edgeReviewEnabled,
    bool? lbwReviewEnabled,
    bool? fullTossAboveWaistIsNoBall,
    bool? bouncedAboveShoulderIsNoBall,
    int? maxBouncersPerOver,
    double? lateralReachMultiplier,
  }) =>
      MatchRules(
        matchId: matchId,
        wideEnabled: wideEnabled ?? this.wideEnabled,
        noBallEnabled: noBallEnabled ?? this.noBallEnabled,
        frontFootNoBallEnabled: frontFootNoBallEnabled ?? this.frontFootNoBallEnabled,
        edgeReviewEnabled: edgeReviewEnabled ?? this.edgeReviewEnabled,
        lbwReviewEnabled: lbwReviewEnabled ?? this.lbwReviewEnabled,
        fullTossAboveWaistIsNoBall: fullTossAboveWaistIsNoBall ?? this.fullTossAboveWaistIsNoBall,
        bouncedAboveShoulderIsNoBall:
            bouncedAboveShoulderIsNoBall ?? this.bouncedAboveShoulderIsNoBall,
        maxBouncersPerOver: maxBouncersPerOver ?? this.maxBouncersPerOver,
        lateralReachMultiplier: lateralReachMultiplier ?? this.lateralReachMultiplier,
      );

  /// The same rules for another match (used when a rules template is applied to a new match).
  MatchRules forMatch(String newMatchId) => MatchRules(
        matchId: newMatchId,
        wideEnabled: wideEnabled,
        noBallEnabled: noBallEnabled,
        frontFootNoBallEnabled: frontFootNoBallEnabled,
        edgeReviewEnabled: edgeReviewEnabled,
        lbwReviewEnabled: lbwReviewEnabled,
        fullTossAboveWaistIsNoBall: fullTossAboveWaistIsNoBall,
        bouncedAboveShoulderIsNoBall: bouncedAboveShoulderIsNoBall,
        maxBouncersPerOver: maxBouncersPerOver,
        lateralReachMultiplier: lateralReachMultiplier,
      );

  Map<String, Object?> toJson() => toSyncPayload();

  /// Exactly the keys of API_CONTRACT §5.3 `MATCH_RULES`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'match_id': matchId,
        'wide_enabled': wideEnabled,
        'no_ball_enabled': noBallEnabled,
        'front_foot_no_ball_enabled': frontFootNoBallEnabled,
        'edge_review_enabled': edgeReviewEnabled,
        'lbw_review_enabled': lbwReviewEnabled,
        'full_toss_above_waist_is_no_ball': fullTossAboveWaistIsNoBall,
        'bounced_above_shoulder_is_no_ball': bouncedAboveShoulderIsNoBall,
        'max_bouncers_per_over': maxBouncersPerOver,
        'lateral_reach_multiplier': lateralReachMultiplier,
      };

  @override
  List<Object?> get props => <Object?>[
        matchId,
        wideEnabled,
        noBallEnabled,
        frontFootNoBallEnabled,
        edgeReviewEnabled,
        lbwReviewEnabled,
        fullTossAboveWaistIsNoBall,
        bouncedAboveShoulderIsNoBall,
        maxBouncersPerOver,
        lateralReachMultiplier,
      ];
}
