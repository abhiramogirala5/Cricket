import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/delivery.dart';
import 'package:gully_umpire/domain/models/enums.dart';
import 'package:gully_umpire/domain/scoring/delivery_rules.dart';
import 'package:gully_umpire/domain/scoring/score_engine.dart';

enum BatterStatus { notOut, out, didNotBat }

/// How a batter was dismissed. [bowlerId] is `null` for a run-out (not credited to the bowler).
final class DismissalInfo extends Equatable {
  const DismissalInfo({required this.type, required this.deliveryId, this.bowlerId});

  final DismissalType type;
  final String deliveryId;
  final String? bowlerId;

  @override
  List<Object?> get props => <Object?>[type, deliveryId, bowlerId];
}

final class BatterLine extends Equatable {
  const BatterLine({
    required this.playerId,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.status,
    this.dismissal,
  });

  final String playerId;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final BatterStatus status;
  final DismissalInfo? dismissal;

  /// `runs / balls x 100`, `0` when no ball was faced.
  double get strikeRate => balls == 0 ? 0 : runs / balls * 100;

  bool get hasBatted => status != BatterStatus.didNotBat;

  @override
  List<Object?> get props => <Object?>[playerId, runs, balls, fours, sixes, status, dismissal];
}

final class BowlerLine extends Equatable {
  const BowlerLine({
    required this.playerId,
    required this.legalBalls,
    required this.runsConceded,
    required this.wickets,
  });

  final String playerId;
  final int legalBalls;
  final int runsConceded;
  final int wickets;

  /// `runs conceded / overs`, `0` when no legal ball was bowled.
  double get economy => legalBalls == 0 ? 0 : runsConceded / (legalBalls / ballsPerOver);

  @override
  List<Object?> get props => <Object?>[playerId, legalBalls, runsConceded, wickets];
}

final class ExtrasSummary extends Equatable {
  const ExtrasSummary({
    this.wides = 0,
    this.noBalls = 0,
    this.byes = 0,
    this.legByes = 0,
    this.total = 0,
  });

  /// Runs scored as wides (penalty included).
  final int wides;

  /// Number of no-balls (each carries one penalty run).
  final int noBalls;

  final int byes;
  final int legByes;

  /// Every extra run of the innings (the penalty run of a no-ball included).
  final int total;

  @override
  List<Object?> get props => <Object?>[wides, noBalls, byes, legByes, total];
}

final class FallOfWicket extends Equatable {
  const FallOfWicket({
    required this.wicketNumber,
    required this.teamScore,
    required this.playerId,
    required this.legalBalls,
  });

  final int wicketNumber;
  final int teamScore;
  final String playerId;

  /// Legal balls bowled when the wicket fell (format with `formatOvers`).
  final int legalBalls;

  @override
  List<Object?> get props => <Object?>[wicketNumber, teamScore, playerId, legalBalls];
}

/// Batting and bowling figures of one innings, derived from its non-voided deliveries
/// (docs/SCORING_RULES.md §7).
final class InningsScorecard extends Equatable {
  const InningsScorecard({
    required this.total,
    required this.batters,
    required this.bowlers,
    required this.extras,
    required this.fallOfWickets,
  });

  /// Builds the scorecard.
  ///
  /// * [battingOrder] lists the batting team (in batting order) so that players who have not
  ///   batted can be shown as "did not bat".
  /// * [atCrease] are batters who are waiting at the crease but have not been part of a ball yet.
  factory InningsScorecard.build({
    required List<Delivery> deliveries,
    required List<String> battingOrder,
    Iterable<String> atCrease = const <String>[],
  }) {
    final List<Delivery> active = deliveries.where((Delivery d) => !d.isVoided).toList();
    active.sort((Delivery a, Delivery b) => a.deliverySequence.compareTo(b.deliverySequence));

    final Map<String, _BatterAccumulator> batters = <String, _BatterAccumulator>{};
    final Map<String, _BowlerAccumulator> bowlers = <String, _BowlerAccumulator>{};
    final List<FallOfWicket> fallOfWickets = <FallOfWicket>[];

    int wides = 0;
    int noBalls = 0;
    int byes = 0;
    int legByes = 0;
    int extrasTotal = 0;
    int runningScore = 0;
    int runningLegalBalls = 0;
    int wicketNumber = 0;

    for (final Delivery d in active) {
      final _BatterAccumulator striker =
          batters.putIfAbsent(d.strikerId, () => _BatterAccumulator(d.strikerId));
      final String? nonStrikerId = d.nonStrikerId;
      if (nonStrikerId != null) {
        batters.putIfAbsent(nonStrikerId, () => _BatterAccumulator(nonStrikerId));
      }
      final _BowlerAccumulator bowler =
          bowlers.putIfAbsent(d.bowlerId, () => _BowlerAccumulator(d.bowlerId));

      // Batter: runs off the bat, balls faced (everything except wides), boundaries.
      striker.runs += d.runsBat;
      if (!d.isWide) {
        striker.balls += 1;
      }
      if (d.runsBat == 4) {
        striker.fours += 1;
      }
      if (d.runsBat == 6) {
        striker.sixes += 1;
      }

      // Bowler: byes and leg-byes are not charged to the bowler.
      if (d.isLegal) {
        bowler.legalBalls += 1;
      }
      bowler.runsConceded += d.runsBat + (d.isWide ? d.runsExtras : 0) + (d.isNoBall ? 1 : 0);

      // Extras.
      if (d.isWide) {
        wides += d.runsExtras;
      }
      if (d.isNoBall) {
        noBalls += 1;
      }
      if (d.isBye) {
        byes += d.runsExtras - d.penaltyRuns;
      }
      if (d.isLegBye) {
        legByes += d.runsExtras - d.penaltyRuns;
      }
      extrasTotal += d.runsExtras;

      runningScore += d.totalRuns;
      if (d.isLegal) {
        runningLegalBalls += 1;
      }

      if (d.isWicket) {
        wicketNumber += 1;
        final String? dismissedId = d.dismissedPlayerId;
        final DismissalType? type = d.dismissalType;
        if (dismissedId != null && type != null) {
          final _BatterAccumulator out =
              batters.putIfAbsent(dismissedId, () => _BatterAccumulator(dismissedId));
          out.dismissal = DismissalInfo(
            type: type,
            deliveryId: d.id,
            bowlerId: type.isBowlerWicket ? d.bowlerId : null,
          );
          if (type.isBowlerWicket) {
            bowler.wickets += 1;
          }
          fallOfWickets.add(
            FallOfWicket(
              wicketNumber: wicketNumber,
              teamScore: runningScore,
              playerId: dismissedId,
              legalBalls: runningLegalBalls,
            ),
          );
        }
      }
    }

    for (final String id in atCrease) {
      batters.putIfAbsent(id, () => _BatterAccumulator(id));
    }

    final List<BatterLine> batterLines = <BatterLine>[
      for (final _BatterAccumulator acc in batters.values) acc.toLine(),
    ];
    for (final String id in battingOrder) {
      if (!batters.containsKey(id)) {
        batterLines.add(
          BatterLine(
            playerId: id,
            runs: 0,
            balls: 0,
            fours: 0,
            sixes: 0,
            status: BatterStatus.didNotBat,
          ),
        );
      }
    }

    return InningsScorecard(
      total: ScoreEngine.aggregate(active),
      batters: batterLines,
      bowlers: <BowlerLine>[for (final _BowlerAccumulator acc in bowlers.values) acc.toLine()],
      extras: ExtrasSummary(
        wides: wides,
        noBalls: noBalls,
        byes: byes,
        legByes: legByes,
        total: extrasTotal,
      ),
      fallOfWickets: fallOfWickets,
    );
  }

  final InningsAggregate total;
  final List<BatterLine> batters;
  final List<BowlerLine> bowlers;
  final ExtrasSummary extras;
  final List<FallOfWicket> fallOfWickets;

  Iterable<BatterLine> get didNotBat =>
      batters.where((BatterLine line) => line.status == BatterStatus.didNotBat);

  @override
  List<Object?> get props => <Object?>[total, batters, bowlers, extras, fallOfWickets];
}

class _BatterAccumulator {
  _BatterAccumulator(this.playerId);

  final String playerId;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  DismissalInfo? dismissal;

  BatterLine toLine() => BatterLine(
        playerId: playerId,
        runs: runs,
        balls: balls,
        fours: fours,
        sixes: sixes,
        status: dismissal == null ? BatterStatus.notOut : BatterStatus.out,
        dismissal: dismissal,
      );
}

class _BowlerAccumulator {
  _BowlerAccumulator(this.playerId);

  final String playerId;
  int legalBalls = 0;
  int runsConceded = 0;
  int wickets = 0;

  BowlerLine toLine() => BowlerLine(
        playerId: playerId,
        legalBalls: legalBalls,
        runsConceded: runsConceded,
        wickets: wickets,
      );
}
