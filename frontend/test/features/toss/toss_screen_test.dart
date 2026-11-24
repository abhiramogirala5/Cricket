import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/data/repositories/match_repository.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/toss/presentation/toss_screen.dart';

import '../../support/bundle_fixtures.dart';

class _FakeMatchRepo implements MatchRepository {
  Toss? recordedToss;

  @override
  Future<Toss> recordToss({
    required String matchId,
    required TossSide callChoice,
    required TossSide result,
    required String winnerTeamId,
    required TossDecision winnerDecision,
    String? calledByPlayerId,
  }) async {
    final Toss toss = Toss(
      id: 'toss-1',
      matchId: matchId,
      callChoice: callChoice,
      result: result,
      winnerTeamId: winnerTeamId,
      winnerDecision: winnerDecision,
      calledByPlayerId: calledByPlayerId,
      createdAt: DateTime.utc(2026, 10, 8),
    );
    recordedToss = toss;
    return toss;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('TossScreen displays 3D coin, allows flip and decision saving', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final MatchBundle bundle = makeBundle(
      status: MatchStatus.draft,
      toss: null,
      innings: const <Innings>[],
    );
    final _FakeMatchRepo fakeRepo = _FakeMatchRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          matchBundleProvider(bundle.match.id).overrideWith(
            (ref) => bundle,
          ),
          matchRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: TossScreen(matchId: bundle.match.id),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Match Toss'), findsOneWidget);
    expect(find.text('1. Who calls the toss?'), findsOneWidget);
    expect(find.text('Reds'), findsOneWidget);
    expect(find.text('Blues'), findsOneWidget);
    expect(find.text('HEADS'), findsWidgets);
    expect(find.text('TAILS'), findsWidgets);
    expect(find.text('FLIP COIN'), findsOneWidget);

    // Tap FLIP COIN button
    await tester.tap(find.text('FLIP COIN'));
    await tester.pump(); // starts flip
    expect(find.text('FLIPPING IN THE AIR…'), findsOneWidget);

    // Advance flip animation past 1600ms
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 100));

    // The coin has landed! Winner section appears
    expect(find.textContaining('won the toss!'), findsOneWidget);
    expect(find.text('BAT FIRST'), findsOneWidget);
    expect(find.text('BOWL FIRST'), findsOneWidget);
    expect(find.text('Save Toss & Continue'), findsOneWidget);

    // Select BOWL FIRST
    await tester.tap(find.text('BOWL FIRST'));
    await tester.pump();

    // Tap Save Toss & Continue
    await tester.tap(find.text('Save Toss & Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fakeRepo.recordedToss, isNotNull);
    expect(fakeRepo.recordedToss?.winnerDecision, TossDecision.bowl);
  });

  testWidgets('TossScreen allows manual coin outcome selection', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final MatchBundle bundle = makeBundle(
      status: MatchStatus.draft,
      toss: null,
      innings: const <Innings>[],
    );
    final _FakeMatchRepo fakeRepo = _FakeMatchRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          matchBundleProvider(bundle.match.id).overrideWith(
            (ref) => bundle,
          ),
          matchRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: TossScreen(matchId: bundle.match.id),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Tap discreet toggle to reveal manual options
    await tester.tap(find.text('Tossed a real coin? Select outcome directly'));
    await tester.pumpAndSettle();

    expect(find.text('Real coin: Heads'), findsOneWidget);
    expect(find.text('Real coin: Tails'), findsOneWidget);

    // Tap Real coin: Tails
    await tester.tap(find.text('Real coin: Tails'));
    await tester.pumpAndSettle();

    expect(find.textContaining('won the toss!'), findsOneWidget);
    expect(find.text('Save Toss & Continue'), findsOneWidget);
  });
}
