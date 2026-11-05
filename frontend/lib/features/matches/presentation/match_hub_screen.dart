import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/cv_providers.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/dialogs.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/core/widgets/section_header.dart';
import 'package:gully_umpire/core/widgets/simulation_badge.dart';
import 'package:gully_umpire/core/widgets/status_chip.dart';
import 'package:gully_umpire/cv/engine/cv_engine.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/match_result.dart';
import 'package:gully_umpire/features/matches/match_flow.dart';
import 'package:gully_umpire/features/matches/match_presentation.dart';

enum _HubAction { scorecard, abandon, delete }

/// One match: where it stands, the next step, the squads, and the less common actions.
class MatchHubScreen extends ConsumerStatefulWidget {
  const MatchHubScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchHubScreen> createState() => _MatchHubScreenState();
}

class _MatchHubScreenState extends ConsumerState<MatchHubScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _perform(MatchBundle bundle, MatchStep step) async {
    switch (step.kind) {
      case MatchStepKind.scan:
        await context.push(Routes.autoScan(widget.matchId));
      case MatchStepKind.toss:
        await context.push(Routes.toss(widget.matchId));
      case MatchStepKind.startFirstInnings:
      case MatchStepKind.startSecondInnings:
        final String? batting = step.battingTeamId;
        if (batting == null) {
          return;
        }
        await _run(() async {
          await ref
              .read(matchRepositoryProvider)
              .startInnings(matchId: widget.matchId, battingTeamId: batting);
          if (mounted) {
            await context.push(Routes.live(widget.matchId));
          }
        });
      case MatchStepKind.score:
        await context.push(Routes.live(widget.matchId));
      case MatchStepKind.finish:
        await _finish(bundle);
      case MatchStepKind.scorecard:
        await context.push(Routes.scorecard(widget.matchId));
    }
  }

  Future<void> _finish(MatchBundle bundle) async {
    final bool confirmed = await confirmAction(
      context,
      title: 'Finish the match?',
      message: 'The result will be worked out from both innings. You cannot score more balls '
          'after this.',
      confirmLabel: 'Finish match',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(() async {
      final MatchResult result =
          await ref.read(matchRepositoryProvider).completeMatch(widget.matchId);
      if (mounted) {
        showMessage(context, result.summary);
      }
    });
  }

  Future<void> _abandon() async {
    final bool confirmed = await confirmAction(
      context,
      title: 'Abandon this match?',
      message: 'The match ends now without a result. The balls already scored are kept.',
      confirmLabel: 'Abandon',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(() async {
      await ref.read(matchRepositoryProvider).abandonMatch(widget.matchId);
    });
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmAction(
      context,
      title: 'Delete this match?',
      message: 'The match, its scorecard and every ball will be removed from this phone and '
          'from your account. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(() async {
      await ref.read(matchRepositoryProvider).deleteMatch(widget.matchId);
      if (!mounted) {
        return;
      }
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.matches);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<MatchBundle?> value = ref.watch(matchBundleProvider(widget.matchId));
    final MatchBundle? bundle = value.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Match'),
        actions: <Widget>[
          if (bundle != null)
            PopupMenuButton<_HubAction>(
              tooltip: 'More',
              onSelected: (_HubAction action) {
                switch (action) {
                  case _HubAction.scorecard:
                    context.push(Routes.scorecard(widget.matchId));
                  case _HubAction.abandon:
                    _abandon();
                  case _HubAction.delete:
                    _delete();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<_HubAction>>[
                if (bundle.innings.isNotEmpty)
                  const PopupMenuItem<_HubAction>(
                    value: _HubAction.scorecard,
                    child: Text('Scorecard'),
                  ),
                if (!bundle.match.isFinished)
                  const PopupMenuItem<_HubAction>(
                    value: _HubAction.abandon,
                    child: Text('Abandon match'),
                  ),
                const PopupMenuItem<_HubAction>(
                  value: _HubAction.delete,
                  child: Text('Delete match'),
                ),
              ],
            ),
        ],
      ),
      body: AsyncBody<MatchBundle?>(
        value: value,
        onRetry: () => ref.invalidate(matchBundleProvider(widget.matchId)),
        builder: (BuildContext context, MatchBundle? data) {
          if (data == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Match not found',
              message: 'It may have been deleted.',
            );
          }
          return _HubContent(
            bundle: data,
            busy: _busy,
            onStep: (MatchStep step) => _perform(data, step),
            onSkipScan: () => context.push(Routes.toss(widget.matchId)),
            onEditToss: () => context.push(Routes.toss(widget.matchId)),
            onScorecard: () => context.push(Routes.scorecard(widget.matchId)),
          );
        },
      ),
    );
  }
}

class _HubContent extends ConsumerWidget {
  const _HubContent({
    required this.bundle,
    required this.busy,
    required this.onStep,
    required this.onSkipScan,
    required this.onEditToss,
    required this.onScorecard,
  });

  final MatchBundle bundle;
  final bool busy;
  final void Function(MatchStep step) onStep;
  final VoidCallback onSkipScan;
  final VoidCallback onEditToss;
  final VoidCallback onScorecard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CvEngine engine = ref.watch(cvEngineProvider);
    final TextTheme text = Theme.of(context).textTheme;
    final CricketMatch match = bundle.match;
    final MatchStep step = nextMatchStep(
      bundle,
      scanAvailable: engine.isAvailable,
      markByHand: engine.mode == CvMode.live,
    );
    final colors = statusColors(match.status);
    final String? title = match.matchName?.trim();
    final String heading = (title == null || title.isEmpty)
        ? '${bundle.teamA.name} vs ${bundle.teamB.name}'
        : title;
    final String? place = match.locationName?.trim();

    return ScreenBody(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                heading,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
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
        Text(
          <String>[
            '${match.oversPerInnings} overs',
            if (place != null && place.isNotEmpty) place,
            matchDateLabel(match),
          ].join(' · '),
          style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ScoreCard(bundle: bundle),
        const SizedBox(height: AppSpacing.lg),
        if (!match.isFinished || bundle.innings.isNotEmpty) ...<Widget>[
          Text(step.hint, style: text.bodyMedium?.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: busy ? null : () => onStep(step),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(step.label),
          ),
        ],
        if (step.kind == MatchStepKind.scan) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: busy ? null : onSkipScan,
            child: const Text('Skip, I will score by hand'),
          ),
        ],
        if (bundle.toss != null && bundle.innings.isEmpty && !match.isFinished) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          TextButton(onPressed: busy ? null : onEditToss, child: const Text('Change the toss')),
        ],
        if (bundle.innings.isNotEmpty && !match.isFinished) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: onScorecard, child: const Text('View scorecard')),
        ],
        const SectionHeader('Umpire assistant'),
        _AssistantCard(
          bundle: bundle,
          engine: engine,
          onMark: engine.mode == CvMode.live && !match.isFinished
              ? () => context.push(Routes.autoScan(match.id))
              : null,
        ),
        const SectionHeader('Teams'),
        _SquadCard(bundle: bundle, teamId: bundle.teamA.id),
        const SizedBox(height: AppSpacing.md),
        _SquadCard(bundle: bundle, teamId: bundle.teamB.id),
        if (bundle.toss != null) ...<Widget>[
          const SectionHeader('Toss'),
          _TossCard(bundle: bundle),
        ],
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.bundle});

  final MatchBundle bundle;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? result = bundle.match.resultSummary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (bundle.innings.isEmpty)
              Text(
                'No balls bowled yet.',
                style: text.bodyLarge?.copyWith(color: AppColors.inkMuted),
              )
            else
              for (final Innings innings in bundle.innings) ...<Widget>[
                Text(
                  inningsScoreLine(bundle.teamName(innings.battingTeamId), innings),
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
            if (result != null && result.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
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

class _AssistantCard extends StatelessWidget {
  const _AssistantCard({required this.bundle, required this.engine, this.onMark});

  final MatchBundle bundle;
  final CvEngine engine;

  /// Opens the stump marking page (only offered with the live camera).
  final VoidCallback? onMark;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final WicketDetection? wicket = bundle.activeWicket;
    final bool live = engine.mode == CvMode.live;
    final String message;
    if (!engine.isAvailable) {
      message = 'The umpire camera is off on this phone. You score every ball yourself.';
    } else if (wicket == null) {
      message = live
          ? 'The stumps have not been marked yet. Mark them once and the camera follows every '
              'ball, suggests wides and no-balls, and keeps a replay.'
          : 'The pitch has not been scanned yet.';
    } else if (live) {
      message = '${wicket.wicketFamily.label} marked. The camera follows every ball, suggests '
          'wides and no-balls, and keeps a replay. You always make the final call.';
    } else {
      final ScanReadiness readiness = ScanReadiness.fromConfidence(wicket.finalConfidence);
      message = '${wicket.wicketFamily.label} found (${formatPercent(wicket.finalConfidence)} '
          'sure). ${readiness.label}.';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.sports, color: AppColors.pitchGreen),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(message, style: text.bodyMedium)),
                if (engine.isSimulated) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  const SimulationBadge(),
                ],
              ],
            ),
            if (onMark != null && wicket != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onMark,
                  icon: const Icon(Icons.crop_free, size: 18),
                  label: const Text('Mark the stumps again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SquadCard extends StatelessWidget {
  const _SquadCard({required this.bundle, required this.teamId});

  final MatchBundle bundle;
  final String teamId;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<MatchPlayer> squad = bundle.squad(teamId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              bundle.teamName(teamId),
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (int i = 0; i < squad.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${i + 1}. ${bundle.playerName(squad[i].playerId)}'
                  '${squad[i].isCaptain ? ' (c)' : ''}'
                  '${squad[i].isWicketkeeper ? ' (wk)' : ''}',
                  style: text.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TossCard extends StatelessWidget {
  const _TossCard({required this.bundle});

  final MatchBundle bundle;

  @override
  Widget build(BuildContext context) {
    final Toss toss = bundle.toss!;
    final String? winner = toss.winnerTeamId;
    final TossDecision? decision = toss.winnerDecision;
    final String line = (winner == null || decision == null)
        ? 'The coin landed ${toss.result.label.toLowerCase()}.'
        : '${bundle.teamName(winner)} won the toss and chose to ${decision.label}.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: <Widget>[
            const Icon(Icons.monetization_on_outlined, color: AppColors.creaseAmber),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(line, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
