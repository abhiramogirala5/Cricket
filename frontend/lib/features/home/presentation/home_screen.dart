import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/cv_providers.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/di/session_providers.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/core/widgets/section_header.dart';
import 'package:gully_umpire/cv/engine/cv_engine.dart';
import 'package:gully_umpire/domain/aggregates/match_list_item.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';
import 'package:gully_umpire/features/matches/match_presentation.dart';
import 'package:gully_umpire/features/matches/presentation/match_card.dart';
import 'package:gully_umpire/features/sync/presentation/sync_status_tile.dart';

/// The first page: start a match, pick up where you left off, see the latest results.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String greeting(UserProfile? user) {
    final String? name = user?.displayName.trim();
    if (name == null || name.isEmpty) {
      return 'Ready to play?';
    }
    return 'Hi, ${name.split(RegExp(r'\s+')).first}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserProfile? user = ref.watch(currentUserProvider);
    final CvEngine engine = ref.watch(cvEngineProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Gully Umpire')),
      body: AsyncBody<List<MatchListItem>>(
        value: ref.watch(matchListProvider),
        onRetry: () => ref.invalidate(matchListProvider),
        builder: (BuildContext context, List<MatchListItem> items) {
          final MatchListItem? resume = resumableMatch(items);
          final List<MatchListItem> finished = items
              .where((MatchListItem item) => !item.isOpen)
              .take(3)
              .toList(growable: false);
          return ScreenBody(
            children: <Widget>[
              Text(
                greeting(user),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Score your match, ball by ball.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkMuted,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () => context.push(Routes.createMatch),
                icon: const Icon(Icons.add),
                label: const Text('Start a new match'),
              ),
              if (engine.isSimulated) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                const MessageBanner(
                  kind: BannerKind.info,
                  title: 'Simulated umpiring',
                  message: 'This is a test build. The umpire assistant plays back made-up '
                      'detections and does not look at a real camera.',
                ),
              ],
              if (resume != null) ...<Widget>[
                const SectionHeader('Pick up where you left off'),
                MatchCard(
                  item: resume,
                  onTap: () => context.push(Routes.match(resume.match.id)),
                ),
              ],
              if (finished.isNotEmpty) ...<Widget>[
                SectionHeader(
                  'Latest results',
                  actionLabel: 'See all',
                  onAction: () => context.go(Routes.matches),
                ),
                for (final MatchListItem item in finished) ...<Widget>[
                  MatchCard(
                    item: item,
                    onTap: () => context.push(Routes.match(item.match.id)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
              const SectionHeader('Your data'),
              SyncStatusTile(onTap: () => context.go(Routes.profile)),
            ],
          );
        },
      ),
    );
  }
}
