import 'dart:convert';
import 'dart:io';

import 'package:gully_umpire/domain/models/models.dart';

const String strikerId = 'player-striker';
const String nonStrikerId = 'player-non-striker';
const String bowlerId = 'player-bowler';
const String inningsId = 'innings-1';
const String matchId = 'match-1';

final DateTime fixedNow = DateTime.utc(2026, 10, 8, 7, 33);

/// Loads docs/scoring_test_vectors.json (tests run with the `frontend` folder as working dir).
Map<String, Object?> loadScoringVectors() {
  final File file = File('../docs/scoring_test_vectors.json');
  if (!file.existsSync()) {
    throw StateError('Cannot find ${file.absolute.path}. Run `flutter test` inside frontend/.');
  }
  final Object? decoded = jsonDecode(file.readAsStringSync());
  return (decoded! as Map<Object?, Object?>).cast<String, Object?>();
}

/// Applies the vector `delivery_defaults` to a partial delivery.
Map<String, Object?> completeVector(
  Map<String, Object?> vectors,
  Map<String, Object?> partial,
) {
  final Map<String, Object?> defaults =
      (vectors['delivery_defaults']! as Map<Object?, Object?>).cast<String, Object?>();
  return <String, Object?>{...defaults, ...partial};
}

/// Turns a complete vector into a [DeliveryDraft]; `dismissed` is resolved to a player id
/// (only for wickets, like the backend harness does).
DeliveryDraft draftFromVector(Map<String, Object?> full) {
  final bool isWicket = full['is_wicket']! as bool;
  final Object? dismissalWire = full['dismissal_type'];
  final bool strikerDismissed = full['dismissed'] == 'STRIKER';
  return DeliveryDraft(
    bowlerId: bowlerId,
    strikerId: strikerId,
    nonStrikerId: nonStrikerId,
    runsBat: full['runs_bat']! as int,
    runsExtras: full['runs_extras']! as int,
    isWide: full['is_wide']! as bool,
    isNoBall: full['is_no_ball']! as bool,
    isBye: full['is_bye']! as bool,
    isLegBye: full['is_leg_bye']! as bool,
    isWicket: isWicket,
    dismissalType: DismissalType.fromWireOrNull(dismissalWire),
    dismissedPlayerId: isWicket ? (strikerDismissed ? strikerId : nonStrikerId) : null,
  );
}

Innings makeInnings({String id = inningsId, DateTime? endedAt}) => Innings(
      id: id,
      matchId: matchId,
      inningsNumber: 1,
      battingTeamId: 'team-a',
      bowlingTeamId: 'team-b',
      startedAt: fixedNow,
      endedAt: endedAt,
    );

/// A stored delivery with sensible defaults; override only what a test cares about.
Delivery makeDelivery({
  int sequence = 1,
  int over = 0,
  int? ball = 1,
  String bowler = bowlerId,
  String striker = strikerId,
  String? nonStriker = nonStrikerId,
  int runsBat = 0,
  int runsExtras = 0,
  bool wide = false,
  bool noBall = false,
  bool bye = false,
  bool legBye = false,
  bool wicket = false,
  DismissalType? dismissal,
  String? dismissedId,
  bool voided = false,
  String? id,
}) =>
    Delivery(
      id: id ?? 'delivery-$sequence',
      inningsId: inningsId,
      deliverySequence: sequence,
      overNumber: over,
      legalBallNumber: (wide || noBall) ? null : ball,
      bowlerId: bowler,
      strikerId: striker,
      nonStrikerId: nonStriker,
      runsBat: runsBat,
      runsExtras: runsExtras,
      isWide: wide,
      isNoBall: noBall,
      isBye: bye,
      isLegBye: legBye,
      isWicket: wicket,
      dismissalType: dismissal,
      dismissedPlayerId: dismissedId,
      isVoided: voided,
      createdAt: fixedNow,
    );
