import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/app/router/app_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/repositories/match_repository.dart';
import 'package:gully_umpire/data/repositories/roster_repository.dart';
import 'package:gully_umpire/data/session/active_session.dart';
import 'package:gully_umpire/data/session/session_manager.dart';

import '../support/data_test_support.dart';

void main() {
  late ActiveSession active;

  setUp(() async {
    final LocalStore store = await openMemoryStore();
    final FakeClock clock = FakeClock();
    final SequenceIds ids = SequenceIds();
    active = ActiveSession(
      userId: 'user-1',
      isLocal: false,
      store: store,
      roster: RosterRepository(store: store, clock: clock, ids: ids, syncEnabled: false),
      matches: MatchRepository(store: store, clock: clock, ids: ids, syncEnabled: false),
    );
  });

  tearDown(() async {
    await active.dispose();
  });

  AsyncValue<SessionView> signedIn() => AsyncData<SessionView>(SessionView(active: active));
  const AsyncValue<SessionView> signedOut = AsyncData<SessionView>(SessionView.signedOut);

  group('while the saved account is being opened', () {
    final List<AsyncValue<SessionView>> notReady = <AsyncValue<SessionView>>[
      const AsyncLoading<SessionView>(),
      AsyncError<SessionView>(Exception('boom'), StackTrace.empty),
    ];

    test('only the splash page is shown', () {
      for (final AsyncValue<SessionView> state in notReady) {
        expect(redirectFor(session: state, location: Routes.splash), isNull);
        expect(redirectFor(session: state, location: Routes.home), Routes.splash);
        expect(redirectFor(session: state, location: Routes.signIn), Routes.splash);
        expect(redirectFor(session: state, location: '/match/abc/live'), Routes.splash);
      }
    });
  });

  group('signed out', () {
    test('may open the sign-in and sign-up pages', () {
      expect(redirectFor(session: signedOut, location: Routes.signIn), isNull);
      expect(redirectFor(session: signedOut, location: Routes.signUp), isNull);
    });

    test('is sent to sign in from everywhere else', () {
      for (final String location in <String>[
        Routes.splash,
        Routes.home,
        Routes.matches,
        Routes.profile,
        Routes.reauth,
        Routes.createMatch,
        Routes.players,
        Routes.match('m1'),
        Routes.live('m1'),
      ]) {
        expect(
          redirectFor(session: signedOut, location: location),
          Routes.signIn,
          reason: location,
        );
      }
    });
  });

  group('signed in (or running without an account)', () {
    test('is sent home from the splash and the sign-in pages', () {
      for (final String location in <String>[Routes.splash, Routes.signIn, Routes.signUp]) {
        expect(redirectFor(session: signedIn(), location: location), Routes.home, reason: location);
      }
    });

    test('may open every other page', () {
      for (final String location in <String>[
        Routes.home,
        Routes.matches,
        Routes.profile,
        Routes.reauth,
        Routes.createMatch,
        Routes.players,
        Routes.syncIssues,
        Routes.match('m1'),
        Routes.toss('m1'),
        Routes.live('m1'),
        Routes.scorecard('m1'),
        Routes.review('m1', 'd1'),
      ]) {
        expect(redirectFor(session: signedIn(), location: location), isNull, reason: location);
      }
    });
  });
}
