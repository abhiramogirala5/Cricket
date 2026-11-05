import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/shell/app_shell.dart';
import 'package:gully_umpire/core/di/session_providers.dart';
import 'package:gully_umpire/data/session/session_manager.dart';
import 'package:gully_umpire/features/auth/presentation/sign_in_screen.dart';
import 'package:gully_umpire/features/auth/presentation/sign_up_screen.dart';
import 'package:gully_umpire/features/home/presentation/home_screen.dart';
import 'package:gully_umpire/features/live_scoring/presentation/live_scoring_screen.dart';
import 'package:gully_umpire/features/match_setup/presentation/create_match_screen.dart';
import 'package:gully_umpire/features/matches/presentation/match_hub_screen.dart';
import 'package:gully_umpire/features/matches/presentation/matches_screen.dart';
import 'package:gully_umpire/features/players/presentation/players_screen.dart';
import 'package:gully_umpire/features/profile/presentation/profile_screen.dart';
import 'package:gully_umpire/features/review/presentation/delivery_review_screen.dart';
import 'package:gully_umpire/features/replay/presentation/replay_viewer_screen.dart';
import 'package:gully_umpire/features/scene_scan/presentation/scene_scan_screen.dart';
import 'package:gully_umpire/features/scorecard/presentation/scorecard_screen.dart';
import 'package:gully_umpire/features/splash/splash_screen.dart';
import 'package:gully_umpire/features/sync/presentation/sync_issues_screen.dart';
import 'package:gully_umpire/features/toss/presentation/toss_screen.dart';

/// Where a person must be sent, given what the session is doing. `null` means "stay".
///
/// * While the app is still opening the saved account (or failed to) only the splash is shown.
/// * Signed out: only the sign-in and sign-up pages.
/// * Signed in (or in local-only mode): everything except those pages and the splash.
String? redirectFor({required AsyncValue<SessionView> session, required String location}) {
  final SessionView? view = session.valueOrNull;
  if (view == null) {
    return location == Routes.splash ? null : Routes.splash;
  }
  if (!view.isSignedIn) {
    return Routes.isPublic(location) ? null : Routes.signIn;
  }
  if (Routes.isPublic(location) || location == Routes.splash) {
    return Routes.home;
  }
  return null;
}

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  ref.listen<AsyncValue<SessionView>>(sessionControllerProvider, (previous, next) {
    refresh.value += 1;
  });
  ref.onDispose(refresh.dispose);

  final GoRouter router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) => redirectFor(
      session: ref.read(sessionControllerProvider),
      location: state.matchedLocation,
    ),
    errorBuilder: (BuildContext context, GoRouterState state) => const _NotFoundScreen(),
    routes: <RouteBase>[
      GoRoute(
        path: Routes.splash,
        builder: (BuildContext context, GoRouterState state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (BuildContext context, GoRouterState state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (BuildContext context, GoRouterState state) => const SignUpScreen(),
      ),
      GoRoute(
        path: Routes.reauth,
        builder: (BuildContext context, GoRouterState state) =>
            const SignInScreen(reauth: true),
      ),
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.home,
                builder: (BuildContext context, GoRouterState state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.matches,
                builder: (BuildContext context, GoRouterState state) => const MatchesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.profile,
                builder: (BuildContext context, GoRouterState state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      // "create" comes before ":id" so that it is not read as a match id.
      GoRoute(
        path: Routes.createMatch,
        builder: (BuildContext context, GoRouterState state) => const CreateMatchScreen(),
      ),
      GoRoute(
        path: '/match/:id',
        builder: (BuildContext context, GoRouterState state) =>
            MatchHubScreen(matchId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/match/:id/auto-scan',
        builder: (BuildContext context, GoRouterState state) =>
            SceneScanScreen(matchId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/match/:id/toss',
        builder: (BuildContext context, GoRouterState state) =>
            TossScreen(matchId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/match/:id/live',
        builder: (BuildContext context, GoRouterState state) =>
            LiveScoringScreen(matchId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/match/:id/scorecard',
        builder: (BuildContext context, GoRouterState state) =>
            ScorecardScreen(matchId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/match/:id/replay/:replayId',
        builder: (BuildContext context, GoRouterState state) =>
            ReplayViewerScreen(replayId: state.pathParameters['replayId'] ?? ''),
      ),
      GoRoute(
        path: '/match/:id/review/:deliveryId',
        builder: (BuildContext context, GoRouterState state) => DeliveryReviewScreen(
          matchId: state.pathParameters['id'] ?? '',
          deliveryId: state.pathParameters['deliveryId'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.players,
        builder: (BuildContext context, GoRouterState state) => const PlayersScreen(),
      ),
      GoRoute(
        path: Routes.syncIssues,
        builder: (BuildContext context, GoRouterState state) => const SyncIssuesScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('That page does not exist.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Go to the home page'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
