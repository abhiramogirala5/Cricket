import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/domain/aggregates/match_list_item.dart';
import 'package:gully_umpire/features/matches/match_presentation.dart';
import 'package:gully_umpire/features/matches/presentation/match_card.dart';

/// All matches, newest first, with a filter.
class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  MatchFilter _filter = MatchFilter.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.createMatch),
        icon: const Icon(Icons.add),
        label: const Text('New match'),
      ),
      body: AsyncBody<List<MatchListItem>>(
        value: ref.watch(matchListProvider),
        onRetry: () => ref.invalidate(matchListProvider),
        builder: (BuildContext context, List<MatchListItem> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.sports_cricket,
              title: 'No matches yet',
              message: 'Set up a match and start scoring. It only takes a minute.',
              actionLabel: 'Start a match',
              onAction: () => context.push(Routes.createMatch),
            );
          }
          final List<MatchListItem> shown = filterMatches(items, _filter);
          return ScreenBody(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              96,
            ),
            children: <Widget>[
              Wrap(
                spacing: AppSpacing.sm,
                children: <Widget>[
                  for (final MatchFilter filter in MatchFilter.values)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(child: Text('No matches in this list.')),
                )
              else
                for (final MatchListItem item in shown) ...<Widget>[
                  MatchCard(
                    item: item,
                    onTap: () => context.push(Routes.match(item.match.id)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
            ],
          );
        },
      ),
    );
  }
}
