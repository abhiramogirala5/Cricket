import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/core/widgets/section_header.dart';
import 'package:gully_umpire/core/widgets/status_chip.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/features/live_scoring/presentation/over_strip.dart';
import 'package:gully_umpire/features/matches/match_presentation.dart';
import 'package:gully_umpire/features/scorecard/scorecard_text.dart';

/// The full scorecard of a match: batting, bowling, extras, fall of wickets and every ball.
class ScorecardScreen extends ConsumerWidget {
  const ScorecardScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scorecard')),
      body: AsyncBody<MatchBundle?>(
        value: ref.watch(matchBundleProvider(matchId)),
        onRetry: () => ref.invalidate(matchBundleProvider(matchId)),
        builder: (BuildContext context, MatchBundle? bundle) {
          if (bundle == null) {
            return const EmptyState(icon: Icons.search_off, title: 'Match not found');
          }
          if (bundle.innings.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: <Widget>[
                _MatchHeader(bundle: bundle),
                const SizedBox(height: AppSpacing.xl),
                const EmptyState(
                  icon: Icons.scoreboard_outlined,
                  title: 'No balls yet',
                  message: 'The scorecard appears once the first innings starts.',
                ),
              ],
            );
          }
          return _ScorecardTabs(bundle: bundle);
        },
      ),
    );
  }
}

class _ScorecardTabs extends StatelessWidget {
  const _ScorecardTabs({required this.bundle});

  final MatchBundle bundle;

  @override
  Widget build(BuildContext context) {
    final List<Innings> innings = bundle.innings;
    final Widget header = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.sm,
            AppSpacing.screenPadding,
            AppSpacing.sm,
          ),
          child: _MatchHeader(bundle: bundle),
        ),
      ),
    );
    if (innings.length == 1) {
      return Column(
        children: <Widget>[
          header,
          Expanded(child: _InningsView(bundle: bundle, innings: innings.first)),
        ],
      );
    }
    return DefaultTabController(
      key: ValueKey<int>(innings.length),
      length: innings.length,
      child: Column(
        children: <Widget>[
          header,
          TabBar(
            tabs: <Widget>[
              for (final Innings item in innings)
                Tab(text: '${item.inningsNumber}. ${bundle.teamName(item.battingTeamId)}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final Innings item in innings) _InningsView(bundle: bundle, innings: item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.bundle});

  final MatchBundle bundle;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final CricketMatch match = bundle.match;
    final String title = '${bundle.teamA.name} vs ${bundle.teamB.name}';
    final String? place = match.locationName;
    final String details = <String>[
      matchDateLabel(match),
      '${match.oversPerInnings} overs',
      if (place != null && place.isNotEmpty) place,
    ].join(' · ');
    final colors = statusColors(match.status);
    final String? result = match.resultSummary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusChip(
                  label: match.status.label,
                  foreground: colors.foreground,
                  background: colors.background,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(details, style: text.bodySmall?.copyWith(color: AppColors.inkMuted)),
            if (result != null && result.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                result,
                style: text.titleSmall?.copyWith(
                  color: AppColors.pitchGreenDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InningsView extends StatelessWidget {
  const _InningsView({required this.bundle, required this.innings});

  final MatchBundle bundle;
  final Innings innings;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Delivery> deliveries = bundle.deliveriesOf(innings.id);
    final InningsScorecard card = InningsScorecard.build(
      deliveries: deliveries,
      battingOrder: bundle.battingOrderIds(innings.battingTeamId),
    );
    String name(String playerId) => bundle.playerName(playerId);
    final List<BatterLine> batted =
        card.batters.where((BatterLine line) => line.hasBatted).toList(growable: false);
    final List<BatterLine> didNotBat = card.didNotBat.toList(growable: false);
    final List<Delivery> active =
        deliveries.where((Delivery d) => !d.isVoided).toList(growable: false);

    return ScreenBody(
      children: <Widget>[
        Text(
          '${bundle.teamName(innings.battingTeamId)} '
          '${card.total.totalRuns}/${card.total.wickets} '
          '(${formatOvers(card.total.legalBalls)} ov)',
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SectionHeader('Batting'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: <Widget>[
                const _TableHeader(
                  first: 'Batter',
                  columns: <String>['R', 'B', '4s', '6s', 'SR'],
                  widths: <double>[36, 36, 32, 32, 48],
                ),
                const Divider(height: AppSpacing.md),
                if (batted.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Text(
                      'Nobody has batted yet.',
                      style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                    ),
                  ),
                for (final BatterLine line in batted)
                  _TableRow(
                    title: name(line.playerId),
                    subtitle: dismissalText(line, name),
                    emphasise: line.status == BatterStatus.notOut,
                    values: <String>[
                      '${line.runs}',
                      '${line.balls}',
                      '${line.fours}',
                      '${line.sixes}',
                      formatDecimal(line.strikeRate),
                    ],
                    widths: const <double>[36, 36, 32, 32, 48],
                  ),
                const Divider(height: AppSpacing.lg),
                Text(extrasText(card.extras), style: text.bodyMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Total ${card.total.totalRuns}/${card.total.wickets} '
                  '(${formatOvers(card.total.legalBalls)} ov)',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (didNotBat.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Did not bat: ${didNotBat.map((BatterLine l) => name(l.playerId)).join(', ')}',
                    style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (card.fallOfWickets.isNotEmpty) ...<Widget>[
          const SectionHeader('Fall of wickets'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                card.fallOfWickets
                    .map<String>((FallOfWicket fall) => fallOfWicketText(fall, name))
                    .join('   '),
                style: text.bodyMedium,
              ),
            ),
          ),
        ],
        const SectionHeader('Bowling'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: <Widget>[
                const _TableHeader(
                  first: 'Bowler',
                  columns: <String>['O', 'R', 'W', 'Econ'],
                  widths: <double>[40, 36, 32, 52],
                ),
                const Divider(height: AppSpacing.md),
                if (card.bowlers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Text(
                      'Nobody has bowled yet.',
                      style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                    ),
                  ),
                for (final BowlerLine line in card.bowlers)
                  _TableRow(
                    title: name(line.playerId),
                    values: <String>[
                      formatOvers(line.legalBalls),
                      '${line.runsConceded}',
                      '${line.wickets}',
                      formatDecimal(line.economy),
                    ],
                    widths: const <double>[40, 36, 32, 52],
                  ),
              ],
            ),
          ),
        ),
        if (active.isNotEmpty) ...<Widget>[
          const SectionHeader('Ball by ball'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('${pluralize(active.length, 'ball')} bowled'),
              subtitle: const Text('Tap a ball with assistant data to see the details'),
              children: <Widget>[
                for (final Delivery delivery in active.reversed)
                  _BallTile(
                    bundle: bundle,
                    delivery: delivery,
                    inningsDeliveries: deliveries,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.first, required this.columns, required this.widths});

  final String first;
  final List<String> columns;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.inkMuted,
          fontWeight: FontWeight.w700,
        );
    return Row(
      children: <Widget>[
        Expanded(child: Text(first, style: style)),
        for (int i = 0; i < columns.length; i++)
          SizedBox(
            width: widths[i],
            child: Text(columns[i], textAlign: TextAlign.right, style: style),
          ),
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.title,
    required this.values,
    required this.widths,
    this.subtitle,
    this.emphasise = false,
  });

  final String title;
  final String? subtitle;
  final List<String> values;
  final List<double> widths;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? note = subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                if (note != null)
                  Text(
                    note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
                  ),
              ],
            ),
          ),
          for (int i = 0; i < values.length; i++)
            SizedBox(
              width: widths[i],
              child: Text(
                values[i],
                textAlign: TextAlign.right,
                style: text.bodyMedium?.copyWith(
                  fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BallTile extends StatelessWidget {
  const _BallTile({
    required this.bundle,
    required this.delivery,
    required this.inningsDeliveries,
  });

  final MatchBundle bundle;
  final Delivery delivery;
  final List<Delivery> inningsDeliveries;

  @override
  Widget build(BuildContext context) {
    final String label = ballLabel(delivery);
    final colors = ballChipColors(label);
    final bool hasDetails = hasAssistantData(delivery, bundle.decisionsOf(delivery.id));
    return ListTile(
      dense: true,
      leading: Container(
        width: 44,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.foreground,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
      title: Text(ballSentence(delivery, bundle.playerName)),
      subtitle: Text('Over ${overBallLabel(delivery, inningsDeliveries)}'),
      trailing: hasDetails ? const Icon(Icons.chevron_right) : null,
      onTap: hasDetails
          ? () => context.push(Routes.review(bundle.match.id, delivery.id))
          : null,
    );
  }
}
