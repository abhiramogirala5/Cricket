import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/data/sync/sync_state.dart';
import 'package:gully_umpire/features/sync/sync_summary.dart';

/// The frame around the three tabs: a bottom bar and, when something about syncing needs the
/// person's attention, a notice above it.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _select(int index) {
    // Tapping the tab that is already open goes back to its first page.
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const _SyncNotice(),
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _select,
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.sports_cricket_outlined),
                selectedIcon: Icon(Icons.sports_cricket),
                label: 'Matches',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Only shown when the person has to do something: sign in again, or look at refused changes.
class _SyncNotice extends ConsumerWidget {
  const _SyncNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isLocal = ref.watch(appConfigProvider).isLocalMode;
    if (isLocal) {
      return const SizedBox.shrink();
    }
    final SyncState state = ref.watch(syncStateProvider).valueOrNull ?? SyncState.initial;
    final SyncSummary summary = describeSync(state, isLocalMode: false);
    if (state.needsSignIn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: MessageBanner(
          kind: BannerKind.warning,
          message: summary.detail,
          actionLabel: 'Sign in',
          onAction: () => context.push(Routes.reauth),
        ),
      );
    }
    if (state.hasFailed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: MessageBanner(
          kind: BannerKind.error,
          title: summary.title,
          message: summary.detail,
          actionLabel: 'Review',
          onAction: () => context.push(Routes.syncIssues),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
