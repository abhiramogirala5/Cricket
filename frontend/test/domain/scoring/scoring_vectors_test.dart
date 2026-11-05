// Runs the shared executable examples of docs/SCORING_RULES.md. The backend runs the same
// vectors (backend/tests/api/test_sync_vectors.py), so both implementations agree.
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';

import '../../support/scoring_fixtures.dart';

List<Map<String, Object?>> _list(Object? raw) => (raw! as List<Object?>)
    .map((Object? e) => (e! as Map<Object?, Object?>).cast<String, Object?>())
    .toList();

Map<String, Object?> _map(Object? raw) => (raw! as Map<Object?, Object?>).cast<String, Object?>();

void main() {
  final Map<String, Object?> vectors = loadScoringVectors();

  group('valid deliveries', () {
    for (final Map<String, Object?> vector in _list(vectors['valid_deliveries'])) {
      final String name = vector['name']! as String;
      test(name, () {
        final DeliveryDraft draft = draftFromVector(completeVector(vectors, _map(vector['delivery'])));

        expect(validateDeliveryInput(DeliveryInput.fromDraft(draft)), isNull);

        final Delivery built = ScoreEngine.buildDelivery(
          innings: makeInnings(),
          oversPerInnings: 6,
          existing: const <Delivery>[],
          draft: draft,
          id: 'd-1',
          now: fixedNow,
        );
        expect(built.deliverySequence, 1);
        expect(built.overNumber, 0);
      });
    }
  });

  group('invalid deliveries', () {
    for (final Map<String, Object?> vector in _list(vectors['invalid_deliveries'])) {
      final String name = vector['name']! as String;
      test(name, () {
        final DeliveryDraft draft = draftFromVector(completeVector(vectors, _map(vector['delivery'])));

        expect(validateDeliveryInput(DeliveryInput.fromDraft(draft)), isNotNull);

        expect(
          () => ScoreEngine.buildDelivery(
            innings: makeInnings(),
            oversPerInnings: 6,
            existing: const <Delivery>[],
            draft: draft,
            id: 'd-1',
            now: fixedNow,
          ),
          throwsA(
            isA<ScoringException>().having(
              (ScoringException e) => e.code,
              'code',
              vector['expect_error'],
            ),
          ),
        );
      });
    }
  });

  group('valid sequences', () {
    for (final Map<String, Object?> sequence in _list(vectors['valid_sequences'])) {
      final String name = sequence['name']! as String;
      test(name, () {
        final int overs = sequence['overs_per_innings']! as int;
        final Innings innings = makeInnings();
        // Every delivery that was accepted, in add-order (voided ones stay in the list).
        final List<Delivery> all = <Delivery>[];
        int counter = 0;

        for (final Map<String, Object?> step in _list(sequence['steps'])) {
          final String op = step['op']! as String;
          final Object? expectedError = step['expect_error'];

          void run() {
            switch (op) {
              case 'add':
                {
                  counter += 1;
                  final Delivery built = ScoreEngine.buildDelivery(
                    innings: innings,
                    oversPerInnings: overs,
                    existing: all,
                    draft: draftFromVector(completeVector(vectors, _map(step['delivery']))),
                    id: 'd-$counter',
                    now: fixedNow,
                  );
                  all.add(built);
                }
              case 'void_last':
                {
                  final Delivery voided = ScoreEngine.voidLast(existing: all, now: fixedNow);
                  all[all.indexWhere((Delivery d) => d.id == voided.id)] = voided;
                }
              case 'void_index':
                {
                  final int index = step['index']! as int;
                  final Delivery voided = ScoreEngine.voidDelivery(
                    existing: all,
                    deliveryId: all[index].id,
                    now: fixedNow,
                  );
                  all[all.indexWhere((Delivery d) => d.id == voided.id)] = voided;
                }
              default:
                fail('Unknown step op $op');
            }
          }

          if (expectedError == null) {
            run();
          } else {
            expect(
              run,
              throwsA(
                isA<ScoringException>().having(
                  (ScoringException e) => e.code,
                  'code',
                  expectedError,
                ),
              ),
              reason: 'step $op should fail with $expectedError',
            );
          }
        }

        final Map<String, Object?> expected = _map(sequence['expected']);
        final InningsAggregate totals = ScoreEngine.aggregate(all);
        expect(totals.totalRuns, expected['total_runs'], reason: 'total_runs');
        expect(totals.wickets, expected['wickets'], reason: 'wickets');
        expect(totals.legalBalls, expected['legal_balls'], reason: 'legal_balls');

        final List<Map<String, Object?>> expectedDeliveries = _list(expected['deliveries']);
        expect(all.length, expectedDeliveries.length, reason: 'number of recorded deliveries');
        for (int i = 0; i < expectedDeliveries.length; i += 1) {
          final Map<String, Object?> want = expectedDeliveries[i];
          final Delivery got = all[i];
          expect(got.deliverySequence, want['delivery_sequence'], reason: 'sequence of #$i');
          expect(got.overNumber, want['over_number'], reason: 'over of #$i');
          expect(got.legalBallNumber, want['legal_ball_number'], reason: 'ball number of #$i');
          expect(got.isVoided, want['voided'] ?? false, reason: 'voided flag of #$i');
        }
      });
    }
  });
}
