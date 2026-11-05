import 'package:gully_umpire/domain/models/delivery.dart';
import 'package:gully_umpire/domain/models/innings.dart';
import 'package:gully_umpire/domain/scoring/delivery_rules.dart';
import 'package:gully_umpire/domain/scoring/score_engine.dart';
import 'package:gully_umpire/domain/scoring/strike_rules.dart';

/// Why an innings is over by the rules (the scorer can also end it by hand).
enum InningsEndReason {
  allOut,
  oversComplete,
  targetReached;

  String get label {
    switch (this) {
      case InningsEndReason.allOut:
        return 'All out';
      case InningsEndReason.oversComplete:
        return 'Overs complete';
      case InningsEndReason.targetReached:
        return 'Target reached';
    }
  }
}

/// Read model of one innings for the live-scoring screen, derived purely from its deliveries.
///
/// Nothing here is stored: after an app restart or an undo it is rebuilt from the same rows.
final class InningsProgress {
  const InningsProgress({
    required this.aggregate,
    required this.setup,
    required this.currentBowlerId,
    required this.previousOverBowlerId,
    required this.overDeliveries,
    required this.isShowingCompletedOver,
    required this.endReason,
    required this.ballsRemaining,
    required this.maxLegalBalls,
    required this.isClosed,
    required this.runsRequired,
  });

  /// Derives the progress of [innings].
  ///
  /// * [battingPlayerCount] is the size of the batting team in this match; the innings is over
  ///   when `battingPlayerCount - 1` wickets have fallen.
  /// * [firstInningsTotal] is only given in the second innings; the innings is over once the
  ///   chasing team has more runs than that.
  factory InningsProgress.from({
    required Innings innings,
    required int oversPerInnings,
    required int battingPlayerCount,
    required List<Delivery> deliveries,
    int? firstInningsTotal,
  }) {
    final InningsAggregate aggregate = ScoreEngine.aggregate(deliveries);
    final int maxLegalBalls = oversPerInnings * ballsPerOver;
    final int currentOver = aggregate.legalBalls ~/ ballsPerOver;

    // Bowler: the one who bowled the most recent ball (even if it was undone), provided that ball
    // belongs to the over now in progress. Otherwise the over is finished and a new bowler is due.
    final Delivery? latest = ScoreEngine.latest(deliveries);
    String? currentBowlerId;
    if (latest != null && latest.overNumber == currentOver) {
      currentBowlerId = latest.bowlerId;
    }

    String? previousOverBowlerId;
    if (currentOver > 0) {
      final List<Delivery> previousOver = _activeInOver(deliveries, currentOver - 1);
      if (previousOver.isNotEmpty) {
        previousOverBowlerId = previousOver.last.bowlerId;
      }
    }

    List<Delivery> overDeliveries = _activeInOver(deliveries, currentOver);
    bool showingCompleted = false;
    if (overDeliveries.isEmpty && currentOver > 0) {
      overDeliveries = _activeInOver(deliveries, currentOver - 1);
      showingCompleted = true;
    }

    final int wicketLimit = battingPlayerCount - 1 < 1 ? 1 : battingPlayerCount - 1;
    InningsEndReason? endReason;
    if (firstInningsTotal != null && aggregate.totalRuns > firstInningsTotal) {
      endReason = InningsEndReason.targetReached;
    } else if (aggregate.wickets >= wicketLimit) {
      endReason = InningsEndReason.allOut;
    } else if (aggregate.legalBalls >= maxLegalBalls) {
      endReason = InningsEndReason.oversComplete;
    }

    int? runsRequired;
    if (firstInningsTotal != null) {
      final int needed = firstInningsTotal + 1 - aggregate.totalRuns;
      runsRequired = needed < 0 ? 0 : needed;
    }

    final int remaining = maxLegalBalls - aggregate.legalBalls;
    return InningsProgress(
      aggregate: aggregate,
      setup: currentSetup(deliveries),
      currentBowlerId: currentBowlerId,
      previousOverBowlerId: previousOverBowlerId,
      overDeliveries: overDeliveries,
      isShowingCompletedOver: showingCompleted,
      endReason: endReason,
      ballsRemaining: remaining < 0 ? 0 : remaining,
      maxLegalBalls: maxLegalBalls,
      isClosed: innings.isClosed,
      runsRequired: runsRequired,
    );
  }

  final InningsAggregate aggregate;

  /// Batters for the next ball; `null` before the first ball (openers must be chosen).
  final NextBallSetup? setup;

  /// Bowler of the over in progress; `null` when a bowler must be chosen.
  final String? currentBowlerId;

  /// Bowler of the previous over (a bowler does not bowl two overs in a row).
  final String? previousOverBowlerId;

  /// Balls of the over in progress (or of the last finished over, see [isShowingCompletedOver]).
  final List<Delivery> overDeliveries;
  final bool isShowingCompletedOver;

  /// Set when the rules say the innings is over; the scorer can end it earlier by hand.
  final InningsEndReason? endReason;

  final int ballsRemaining;
  final int maxLegalBalls;
  final bool isClosed;

  /// Runs the chasing team still needs to win; `null` in the first innings.
  final int? runsRequired;

  bool get needsOpeners => setup == null;

  bool get needsNewBowler => currentBowlerId == null;

  /// Balls can still be scored.
  bool get canScore => !isClosed && endReason == null;

  /// The rules have ended the innings but it has not been closed yet.
  bool get shouldClose => !isClosed && endReason != null;

  static List<Delivery> _activeInOver(List<Delivery> deliveries, int overNumber) {
    final List<Delivery> inOver = deliveries
        .where((Delivery d) => !d.isVoided && d.overNumber == overNumber)
        .toList();
    inOver.sort((Delivery a, Delivery b) => a.deliverySequence.compareTo(b.deliverySequence));
    return inOver;
  }
}
