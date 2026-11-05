import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/delivery.dart';
import 'package:gully_umpire/domain/models/delivery_draft.dart';
import 'package:gully_umpire/domain/models/innings.dart';
import 'package:gully_umpire/domain/scoring/delivery_rules.dart';

/// Codes of docs/SCORING_RULES.md. Engine-level only: `nothingToVoid` never reaches the server.
abstract final class ScoringErrorCodes {
  static const String invalidDelivery = 'INVALID_DELIVERY';
  static const String invalidReference = 'INVALID_REFERENCE';
  static const String inningsClosed = 'INNINGS_CLOSED';
  static const String overLimitExceeded = 'OVER_LIMIT_EXCEEDED';
  static const String notLastDelivery = 'NOT_LAST_DELIVERY';
  static const String nothingToVoid = 'NOTHING_TO_VOID';
  static const String entityNotFound = 'ENTITY_NOT_FOUND';
}

/// A scoring action that the rules refuse. [message] is safe to show to the scorer.
final class ScoringException implements Exception {
  const ScoringException(this.code, this.message);

  final String code;
  final String message;

  String get userMessage => message;

  @override
  String toString() => 'ScoringException($code): $message';
}

/// Innings totals over the non-voided deliveries (docs/SCORING_RULES.md §5).
final class InningsAggregate extends Equatable {
  const InningsAggregate({this.totalRuns = 0, this.wickets = 0, this.legalBalls = 0});

  static const InningsAggregate empty = InningsAggregate();

  final int totalRuns;
  final int wickets;
  final int legalBalls;

  @override
  List<Object?> get props => <Object?>[totalRuns, wickets, legalBalls];
}

/// Derived fields of a new delivery (docs/SCORING_RULES.md §3).
final class DeliveryPosition extends Equatable {
  const DeliveryPosition({
    required this.deliverySequence,
    required this.overNumber,
    required this.legalBallNumber,
  });

  final int deliverySequence;
  final int overNumber;

  /// `null` for wides and no-balls.
  final int? legalBallNumber;

  @override
  List<Object?> get props => <Object?>[deliverySequence, overNumber, legalBallNumber];
}

/// Pure scoring rules. No I/O, no clock, no random ids: callers pass everything in, so the
/// engine behaves exactly like `backend/app/services/scoring.py`.
abstract final class ScoreEngine {
  /// Totals over the non-voided deliveries.
  static InningsAggregate aggregate(Iterable<Delivery> deliveries) {
    int totalRuns = 0;
    int wickets = 0;
    int legalBalls = 0;
    for (final Delivery delivery in deliveries) {
      if (delivery.isVoided) {
        continue;
      }
      totalRuns += delivery.totalRuns;
      if (delivery.isWicket) {
        wickets += 1;
      }
      if (delivery.isLegal) {
        legalBalls += 1;
      }
    }
    return InningsAggregate(totalRuns: totalRuns, wickets: wickets, legalBalls: legalBalls);
  }

  /// Highest `deliverySequence` ever recorded, voided deliveries included (0 when none).
  static int maxSequence(Iterable<Delivery> deliveries) {
    int highest = 0;
    for (final Delivery delivery in deliveries) {
      if (delivery.deliverySequence > highest) {
        highest = delivery.deliverySequence;
      }
    }
    return highest;
  }

  /// The most recent delivery of any kind (voided included), or `null`.
  static Delivery? latest(Iterable<Delivery> deliveries) {
    Delivery? best;
    for (final Delivery delivery in deliveries) {
      if (best == null || delivery.deliverySequence > best.deliverySequence) {
        best = delivery;
      }
    }
    return best;
  }

  /// The last non-voided delivery, or `null`.
  static Delivery? lastActive(Iterable<Delivery> deliveries) {
    Delivery? best;
    for (final Delivery delivery in deliveries) {
      if (delivery.isVoided) {
        continue;
      }
      if (best == null || delivery.deliverySequence > best.deliverySequence) {
        best = delivery;
      }
    }
    return best;
  }

  /// Sequence, over and ball number the next delivery receives.
  ///
  /// Sequence numbers are never reused (even after an undo); over and ball numbers are.
  static DeliveryPosition nextPosition(Iterable<Delivery> deliveries, {required bool legal}) {
    final int legalBefore = aggregate(deliveries).legalBalls;
    return DeliveryPosition(
      deliverySequence: maxSequence(deliveries) + 1,
      overNumber: legalBefore ~/ ballsPerOver,
      legalBallNumber: legal ? (legalBefore % ballsPerOver) + 1 : null,
    );
  }

  /// Validates [draft] and turns it into a stored [Delivery].
  ///
  /// Order of checks (docs/SCORING_RULES.md §2): rules 1-13, roster membership, innings closed,
  /// over limit. Pass [matchPlayerIds] to enforce the roster check.
  ///
  /// Throws [ScoringException] when a rule is violated.
  static Delivery buildDelivery({
    required Innings innings,
    required int oversPerInnings,
    required List<Delivery> existing,
    required DeliveryDraft draft,
    required String id,
    required DateTime now,
    Set<String>? matchPlayerIds,
  }) {
    final String? problem = validateDeliveryInput(DeliveryInput.fromDraft(draft));
    if (problem != null) {
      throw ScoringException(ScoringErrorCodes.invalidDelivery, problem);
    }

    if (matchPlayerIds != null) {
      final Set<String> wanted = <String>{draft.bowlerId, draft.strikerId};
      final String? nonStrikerId = draft.nonStrikerId;
      if (nonStrikerId != null) {
        wanted.add(nonStrikerId);
      }
      final String? dismissedId = draft.dismissedPlayerId;
      if (dismissedId != null) {
        wanted.add(dismissedId);
      }
      if (!matchPlayerIds.containsAll(wanted)) {
        throw const ScoringException(
          ScoringErrorCodes.invalidReference,
          'The bowler and batters must be players of this match.',
        );
      }
    }

    if (innings.isClosed) {
      throw const ScoringException(ScoringErrorCodes.inningsClosed, 'This innings has ended.');
    }

    final int maxLegalBalls = oversPerInnings * ballsPerOver;
    if (aggregate(existing).legalBalls >= maxLegalBalls) {
      throw ScoringException(
        ScoringErrorCodes.overLimitExceeded,
        'This innings already has all $oversPerInnings overs.',
      );
    }

    final DeliveryPosition position = nextPosition(existing, legal: draft.isLegal);
    return Delivery(
      id: id,
      inningsId: innings.id,
      wicketDetectionId: draft.wicketDetectionId,
      deliverySequence: position.deliverySequence,
      overNumber: position.overNumber,
      legalBallNumber: position.legalBallNumber,
      bowlerId: draft.bowlerId,
      strikerId: draft.strikerId,
      nonStrikerId: draft.nonStrikerId,
      runsBat: draft.runsBat,
      runsExtras: draft.runsExtras,
      isWide: draft.isWide,
      isNoBall: draft.isNoBall,
      isBye: draft.isBye,
      isLegBye: draft.isLegBye,
      isWicket: draft.isWicket,
      dismissalType: draft.dismissalType,
      dismissedPlayerId: draft.dismissedPlayerId,
      speedKmph: draft.speedKmph,
      speedConfidence: draft.speedConfidence,
      ballTrackingConfidence: draft.ballTrackingConfidence,
      poseTrackingConfidence: draft.poseTrackingConfidence,
      wicketTrackingConfidence: draft.wicketTrackingConfidence,
      createdAt: now,
    );
  }

  /// Voids the last non-voided delivery and returns the updated copy.
  ///
  /// Throws `NOTHING_TO_VOID` when there is nothing left to undo.
  static Delivery voidLast({
    required List<Delivery> existing,
    required DateTime now,
    String? reason,
  }) {
    final Delivery? last = lastActive(existing);
    if (last == null) {
      throw const ScoringException(
        ScoringErrorCodes.nothingToVoid,
        'There is no ball to undo.',
      );
    }
    return last.copyWith(isVoided: true, voidedAt: now, voidReason: reason);
  }

  /// Voids [deliveryId], which must be the last non-voided delivery.
  ///
  /// An already voided delivery is never the last active one, so it is refused with
  /// `NOT_LAST_DELIVERY` too (the server treats a repeated void as a no-op instead).
  static Delivery voidDelivery({
    required List<Delivery> existing,
    required String deliveryId,
    required DateTime now,
    String? reason,
  }) {
    final bool known = existing.any((Delivery delivery) => delivery.id == deliveryId);
    if (!known) {
      throw const ScoringException(
        ScoringErrorCodes.entityNotFound,
        'That ball does not exist.',
      );
    }
    final Delivery? last = lastActive(existing);
    if (last == null) {
      throw const ScoringException(
        ScoringErrorCodes.nothingToVoid,
        'There is no ball to undo.',
      );
    }
    if (last.id != deliveryId) {
      throw const ScoringException(
        ScoringErrorCodes.notLastDelivery,
        'Only the most recent ball can be undone.',
      );
    }
    return last.copyWith(isVoided: true, voidedAt: now, voidReason: reason);
  }
}
