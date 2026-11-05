import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/toss_rules.dart';

/// Records who called, what the coin showed and what the winner chose.
class TossScreen extends ConsumerWidget {
  const TossScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('The toss')),
      body: AsyncBody<MatchBundle?>(
        value: ref.watch(matchBundleProvider(matchId)),
        onRetry: () => ref.invalidate(matchBundleProvider(matchId)),
        builder: (BuildContext context, MatchBundle? bundle) {
          if (bundle == null) {
            return const EmptyState(icon: Icons.search_off, title: 'Match not found');
          }
          if (bundle.innings.isNotEmpty || bundle.match.isFinished) {
            return const EmptyState(
              icon: Icons.lock_outline,
              title: 'The toss is locked',
              message: 'It cannot change once the innings has started.',
            );
          }
          return _TossForm(bundle: bundle);
        },
      ),
    );
  }
}

class _TossForm extends ConsumerStatefulWidget {
  const _TossForm({required this.bundle});

  final MatchBundle bundle;

  @override
  ConsumerState<_TossForm> createState() => _TossFormState();
}

class _TossFormState extends ConsumerState<_TossForm> {
  late String _callingTeamId;
  late TossSide _call;
  TossSide? _result;
  late TossDecision _decision;
  bool _flipping = false;
  bool _busy = false;
  String? _error;

  MatchBundle get _bundle => widget.bundle;

  @override
  void initState() {
    super.initState();
    final Toss? toss = _bundle.toss;
    if (toss != null && toss.winnerTeamId != null) {
      final String winner = toss.winnerTeamId!;
      _callingTeamId = toss.callerWon ? winner : _bundle.match.otherTeamId(winner);
      _call = toss.callChoice;
      _result = toss.result;
      _decision = toss.winnerDecision ?? TossDecision.bat;
    } else {
      _callingTeamId = _bundle.teamA.id;
      _call = TossSide.heads;
      _decision = TossDecision.bat;
    }
  }

  String get _otherTeamId => _bundle.match.otherTeamId(_callingTeamId);

  String? get _winnerTeamId {
    final TossSide? result = _result;
    if (result == null) {
      return null;
    }
    return tossWinnerTeamId(
      callingTeamId: _callingTeamId,
      otherTeamId: _otherTeamId,
      call: _call,
      result: result,
    );
  }

  Future<void> _flip() async {
    if (_flipping) {
      return;
    }
    setState(() {
      _flipping = true;
      _result = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) {
      return;
    }
    setState(() {
      _result = Random().nextBool() ? TossSide.heads : TossSide.tails;
      _flipping = false;
    });
  }

  Future<void> _save() async {
    final TossSide? result = _result;
    final String? winner = _winnerTeamId;
    if (_busy || result == null || winner == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? callerId;
      for (final MatchPlayer member in _bundle.squad(_callingTeamId)) {
        if (member.isCaptain) {
          callerId = member.playerId;
          break;
        }
      }
      await ref.read(matchRepositoryProvider).recordToss(
            matchId: _bundle.match.id,
            callChoice: _call,
            result: result,
            winnerTeamId: winner,
            winnerDecision: _decision,
            calledByPlayerId: callerId,
          );
      if (!mounted) {
        return;
      }
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.match(_bundle.match.id));
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? winner = _winnerTeamId;
    final TossSide? result = _result;
    return ScreenBody(
      children: <Widget>[
        Text('Who calls?', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: <ButtonSegment<String>>[
            ButtonSegment<String>(value: _bundle.teamA.id, label: Text(_bundle.teamA.name)),
            ButtonSegment<String>(value: _bundle.teamB.id, label: Text(_bundle.teamB.name)),
          ],
          selected: <String>{_callingTeamId},
          onSelectionChanged: (Set<String> value) => setState(() => _callingTeamId = value.first),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('The call', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<TossSide>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<TossSide>>[
            ButtonSegment<TossSide>(value: TossSide.heads, label: Text('Heads')),
            ButtonSegment<TossSide>(value: TossSide.tails, label: Text('Tails')),
          ],
          selected: <TossSide>{_call},
          onSelectionChanged: (Set<TossSide> value) => setState(() => _call = value.first),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('The coin', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Flip it here, or tap what it showed if you tossed a real coin.',
          style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<TossSide>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: const <ButtonSegment<TossSide>>[
            ButtonSegment<TossSide>(value: TossSide.heads, label: Text('Heads')),
            ButtonSegment<TossSide>(value: TossSide.tails, label: Text('Tails')),
          ],
          selected: result == null ? <TossSide>{} : <TossSide>{result},
          onSelectionChanged: (Set<TossSide> value) => setState(() {
            _result = value.isEmpty ? null : value.first;
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _flipping ? null : _flip,
          icon: _flipping
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.monetization_on_outlined),
          label: Text(_flipping ? 'Flipping…' : 'Flip the coin'),
        ),
        if (winner != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          MessageBanner(
            kind: BannerKind.success,
            title: '${_bundle.teamName(winner)} won the toss',
            message: 'What do they choose?',
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<TossDecision>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<TossDecision>>[
              ButtonSegment<TossDecision>(value: TossDecision.bat, label: Text('Bat first')),
              ButtonSegment<TossDecision>(value: TossDecision.bowl, label: Text('Bowl first')),
            ],
            selected: <TossDecision>{_decision},
            onSelectionChanged: (Set<TossDecision> value) =>
                setState(() => _decision = value.first),
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          MessageBanner(message: _error!, kind: BannerKind.error),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: (_busy || winner == null) ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Save the toss'),
        ),
      ],
    );
  }
}
