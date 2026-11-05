import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/core/di/cv_providers.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/di/live_providers.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/dialogs.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/core/utils/app_log.dart';
import 'package:gully_umpire/core/widgets/simulation_badge.dart';
import 'package:gully_umpire/cv/adapters/mock/mock_scenario.dart';
import 'package:gully_umpire/cv/engine/cv_engine.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart' as ball_kind;
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:gully_umpire/data/repositories/repository_inputs.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/features/live_camera/live_inputs_builder.dart';
import 'package:gully_umpire/features/live_camera/presentation/live_camera_panel.dart';
import 'package:gully_umpire/features/live_scoring/live_board.dart';
import 'package:gully_umpire/features/live_scoring/live_draft_builder.dart';
import 'package:gully_umpire/features/live_scoring/presentation/batters_card.dart';
import 'package:gully_umpire/features/live_scoring/presentation/extras_sheet.dart';
import 'package:gully_umpire/features/live_scoring/presentation/over_strip.dart';
import 'package:gully_umpire/features/live_scoring/presentation/player_picker_sheet.dart';
import 'package:gully_umpire/features/live_scoring/presentation/requirements_card.dart';
import 'package:gully_umpire/features/live_scoring/presentation/run_pad.dart';
import 'package:gully_umpire/features/live_scoring/presentation/scoreboard_card.dart';
import 'package:gully_umpire/features/live_scoring/presentation/simulate_delivery_sheet.dart';
import 'package:gully_umpire/features/live_scoring/presentation/umpire_suggestion_card.dart';
import 'package:gully_umpire/features/live_scoring/presentation/wicket_sheet.dart';
import 'package:gully_umpire/features/umpiring/umpiring_mappers.dart';

enum _ScoringMenu { endInnings }

/// The page the scorer uses ball by ball.
///
/// Everything shown comes from the saved balls (`LiveBoard`); the only things kept in this
/// screen are the choices that are not part of a ball yet (openers, the batter who comes in,
/// the bowler of a new over) and the last look of the umpire assistant.
class LiveScoringScreen extends ConsumerStatefulWidget {
  const LiveScoringScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<LiveScoringScreen> createState() => _LiveScoringScreenState();
}

class _LiveScoringScreenState extends ConsumerState<LiveScoringScreen> {
  final CancellationFlag _cancel = CancellationFlag();
  LiveChoices _choices = const LiveChoices();
  DeliveryAnalysis? _analysis;

  /// The replay file that goes with [_analysis] (kept on the phone until the ball is scored).
  String? _replayId;

  /// The ball that is bowled (read in `build`, used by the helpers that build the camera panel).
  ball_kind.BallKind _ball = ball_kind.BallKind.cricketBall;
  double? _distanceFeet;
  bool _analysing = false;
  bool _busy = false;

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  // ---- Reading the latest state -----------------------------------------------------------

  /// The bundle and board right now, or `null` when the innings cannot be scored (no match, the
  /// match has ended, no innings yet, or the innings is closed).
  ({MatchBundle bundle, LiveBoard board})? _liveNow() {
    final MatchBundle? bundle = ref.read(matchBundleProvider(widget.matchId)).valueOrNull;
    if (bundle == null || bundle.match.isFinished) {
      return null;
    }
    final Innings? innings = bundle.currentInnings;
    if (innings == null || innings.isClosed) {
      return null;
    }
    return (bundle: bundle, board: LiveBoard.from(bundle, innings));
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.match(widget.matchId));
    }
  }

  // ---- Choices ----------------------------------------------------------------------------

  String? _roleLabel(MatchBundle bundle, String playerId) {
    final MatchPlayer? member = bundle.matchPlayerById(playerId);
    if (member == null) {
      return null;
    }
    final List<String> parts = <String>[
      if (member.isCaptain) 'Captain',
      if (member.isWicketkeeper) 'Wicketkeeper',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  List<PickerOption> _batterOptions(MatchBundle bundle, Iterable<String> ids) => <PickerOption>[
        for (final String id in ids)
          PickerOption(
            id: id,
            title: bundle.playerName(id),
            subtitle: _roleLabel(bundle, id),
          ),
      ];

  Future<void> _chooseOpeners(LiveBoard board) async {
    final MatchBundle bundle = board.bundle;
    final List<String> everyone = board.availableBatterIds();
    final String? striker = await showPlayerPicker(
      context,
      title: 'Who faces the first ball?',
      options: _batterOptions(bundle, everyone),
    );
    if (!mounted) {
      return;
    }
    if (striker == null) {
      return;
    }
    final String? nonStriker = await showPlayerPicker(
      context,
      title: 'Who is at the other end?',
      options: _batterOptions(bundle, everyone.where((String id) => id != striker)),
    );
    if (!mounted) {
      return;
    }
    if (nonStriker == null) {
      return;
    }
    setState(() {
      _choices = _choices.copyWith(openerStrikerId: striker, openerNonStrikerId: nonStriker);
    });
  }

  Future<void> _chooseIncomingBatter(LiveBoard board) async {
    final NextBallSetup? setup = board.progress.setup;
    final String? strikerAtCrease = setup?.strikerId;
    final String? nonStrikerAtCrease = setup?.nonStrikerId;
    final List<String> atCrease = <String>[
      if (strikerAtCrease != null) strikerAtCrease,
      if (nonStrikerAtCrease != null) nonStrikerAtCrease,
    ];
    final String? chosen = await showPlayerPicker(
      context,
      title: 'Who comes in to bat?',
      options: _batterOptions(board.bundle, board.availableBatterIds(atCrease: atCrease)),
      emptyMessage: 'Every other batter has already batted.',
    );
    if (!mounted) {
      return;
    }
    if (chosen == null) {
      return;
    }
    setState(() => _choices = _choices.copyWith(incomingBatterId: chosen));
  }

  String _bowlerSubtitle(LiveBoard board, String playerId) {
    final String? role = _roleLabel(board.bundle, playerId);
    final String figures = bowlerFigures(board.bowlerLine(playerId));
    return role == null ? figures : '$figures · $role';
  }

  Future<void> _chooseBowler(LiveBoard board) async {
    final MatchBundle bundle = board.bundle;
    final String? chosen = await showPlayerPicker(
      context,
      title: 'Who bowls this over?',
      options: <PickerOption>[
        for (final String id in board.availableBowlerIds)
          PickerOption(
            id: id,
            title: bundle.playerName(id),
            subtitle: _bowlerSubtitle(board, id),
          ),
      ],
    );
    if (!mounted) {
      return;
    }
    if (chosen == null) {
      return;
    }
    setState(() => _choices = _choices.copyWith(bowlerId: chosen));
  }

  // ---- Scoring ----------------------------------------------------------------------------

  /// Saves one ball with whatever the scorer entered and, when the assistant had looked at it,
  /// the assistant's suggestions next to what was finally scored.
  Future<void> _record({
    BallLegality kind = BallLegality.legal,
    int runs = 0,
    RunsMode mode = RunsMode.bat,
    DismissalType? dismissal,
    String? dismissedPlayerId,
  }) async {
    if (_busy || _analysing) {
      return;
    }
    final ({MatchBundle bundle, LiveBoard board})? live = _liveNow();
    if (live == null) {
      showMessage(context, 'This innings can no longer be scored.');
      return;
    }
    final LiveBoard board = live.board;
    if (!board.progress.canScore) {
      showMessage(context, 'The innings is over. End it from this page to carry on.');
      return;
    }
    final LiveReadiness readiness = board.readiness(_choices);
    final String? striker = readiness.strikerId;
    final String? bowler = readiness.bowlerId;
    if (!readiness.canScore || striker == null || bowler == null) {
      showMessage(context, 'Choose the batters and the bowler first.');
      return;
    }

    setState(() => _busy = true);
    try {
      final DeliveryDraft base = buildDraft(
        bowlerId: bowler,
        strikerId: striker,
        nonStrikerId: readiness.nonStrikerId,
        kind: kind,
        runs: runs,
        runsMode: mode,
        dismissal: dismissal,
        dismissedPlayerId: dismissedPlayerId,
      );
      final DeliveryAnalysis? analysis = _analysis;
      final String? replayId = _replayId;
      final DeliveryDraft draft = draftWithAnalysis(
        base,
        analysis: analysis,
        wicket: live.bundle.activeWicket,
      );
      final Delivery saved = await ref.read(matchRepositoryProvider).recordDelivery(
            inningsId: board.innings.id,
            draft: draft,
            decisions: analysis == null
                ? const <DecisionInput>[]
                : decisionInputsFor(analysis, draft),
            trajectory: analysis == null ? null : trajectoryInputFor(analysis),
          );
      if (replayId != null) {
        await _attachReplay(replayId, saved.id);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _choices = const LiveChoices();
        _analysis = null;
        _replayId = null;
        _busy = false;
      });
      unawaited(HapticFeedback.lightImpact());
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showMessage(context, friendlyError(error));
    }
  }

  Future<void> _onWicket() async {
    final ({MatchBundle bundle, LiveBoard board})? live = _liveNow();
    if (live == null || _busy || _analysing) {
      return;
    }
    final LiveReadiness readiness = live.board.readiness(_choices);
    final String? striker = readiness.strikerId;
    if (!readiness.canScore || striker == null) {
      showMessage(context, 'Choose the batters and the bowler first.');
      return;
    }
    final String? nonStriker = readiness.nonStrikerId;
    final WicketChoice? choice = await showWicketSheet(
      context,
      strikerId: striker,
      strikerName: live.bundle.playerName(striker),
      nonStrikerId: nonStriker,
      nonStrikerName: nonStriker == null ? null : live.bundle.playerName(nonStriker),
    );
    if (!mounted) {
      return;
    }
    if (choice == null) {
      return;
    }
    await _record(
      kind: choice.kind,
      runs: choice.runs,
      dismissal: choice.dismissal,
      dismissedPlayerId: choice.dismissedPlayerId,
    );
  }

  Future<void> _onExtra(ExtraType type) async {
    if (_busy || _analysing) {
      return;
    }
    final ExtraChoice? choice = await showExtrasSheet(context, type: type);
    if (!mounted) {
      return;
    }
    if (choice == null) {
      return;
    }
    await _record(kind: choice.kind, runs: choice.runs, mode: choice.mode);
  }

  Future<void> _undo() async {
    final ({MatchBundle bundle, LiveBoard board})? live = _liveNow();
    if (live == null || _busy || _analysing) {
      return;
    }
    final Delivery? last = live.board.lastActiveBall;
    if (last == null) {
      return;
    }
    final bool confirmed = await confirmAction(
      context,
      title: 'Undo the last ball?',
      message: 'The last ball (${ballLabel(last)}) is taken off the score. You can score it again.',
      confirmLabel: 'Undo ball',
      destructive: true,
    );
    if (!mounted) {
      return;
    }
    if (!confirmed) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(matchRepositoryProvider)
          .undoLastDelivery(live.board.innings.id, reason: 'Undone by the scorer');
      if (!mounted) {
        return;
      }
      setState(() {
        _choices = const LiveChoices();
        _analysis = null;
        _busy = false;
      });
      await _dropPendingReplay();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showMessage(context, friendlyError(error));
    }
  }

  Future<void> _confirmEndInnings() async {
    if (_liveNow() == null || _busy) {
      return;
    }
    final bool confirmed = await confirmAction(
      context,
      title: 'End this innings?',
      message: 'Use this when the innings is over before the rules end it, for example when '
          'time is up. The balls already scored are kept.',
      confirmLabel: 'End innings',
      destructive: true,
    );
    if (!mounted) {
      return;
    }
    if (!confirmed) {
      return;
    }
    await _closeInnings();
  }

  Future<void> _closeInnings() async {
    final ({MatchBundle bundle, LiveBoard board})? live = _liveNow();
    if (live == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(matchRepositoryProvider).closeInnings(live.board.innings.id);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _leave();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showMessage(context, friendlyError(error));
    }
  }

  // ---- Live umpire camera ------------------------------------------------------------------

  /// A delivery the camera followed: show what the assistant made of it and keep its replay on the
  /// phone until the ball is scored.
  void _onDelivery(LiveDeliveryResult result) {
    if (!mounted) {
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _analysis = result.analysis;
      _analysing = false;
    });
    unawaited(_keepReplay(result));
  }

  Future<void> _keepReplay(LiveDeliveryResult result) async {
    final Uint8List? bytes = result.replay;
    final ReplayStore? store = ref.read(replayStoreProvider);
    // The ball before this one was never scored: its replay is not needed any more.
    await _dropPendingReplay();
    if (bytes == null || store == null) {
      return;
    }
    try {
      final String id = ref.read(idGeneratorProvider).newId();
      await store.save(id: id, matchId: widget.matchId, bytes: bytes);
      if (!mounted) {
        await store.delete(id);
        return;
      }
      setState(() => _replayId = id);
    } on Object catch (error) {
      AppLog.warn('The replay could not be kept: ${error.runtimeType}');
    }
  }

  Future<void> _dropPendingReplay() async {
    final String? id = _replayId;
    if (id == null) {
      return;
    }
    _replayId = null;
    try {
      await ref.read(replayStoreProvider)?.delete(id);
    } on Object catch (error) {
      AppLog.warn('An old replay could not be removed: ${error.runtimeType}');
    }
  }

  Future<void> _attachReplay(String replayId, String deliveryId) async {
    try {
      await ref.read(replayStoreProvider)?.attachDelivery(replayId, deliveryId);
      ref.read(replayUploaderProvider)?.kick();
    } on Object catch (error) {
      // The ball is saved; only its replay link is missing.
      AppLog.warn('The replay could not be linked to the ball: ${error.runtimeType}');
    }
  }

  Future<void> _markStumps() {
    return context.push<void>(Routes.autoScan(widget.matchId));
  }

  void _openReplay() {
    final String? id = _replayId;
    if (id != null) {
      unawaited(context.push<void>(Routes.replay(widget.matchId, id)));
    }
  }

  // ---- Simulated umpire assistant (development builds only) -------------------------------

  Future<void> _simulate() async {
    final CvEngine engine = ref.read(cvEngineProvider);
    final ({MatchBundle bundle, LiveBoard board})? live = _liveNow();
    if (engine is! SimulatedCvEngine || live == null || _busy || _analysing) {
      return;
    }
    final WicketDetection? wicket = live.bundle.activeWicket;
    final String? striker = live.board.readiness(_choices).strikerId;
    if (wicket == null || striker == null) {
      return;
    }
    final MockDeliveryKind? kind = await showSimulateDeliverySheet(context);
    if (!mounted) {
      return;
    }
    if (kind == null) {
      return;
    }
    setState(() {
      _analysing = true;
      _analysis = null;
    });
    try {
      final AppConfig config = ref.read(appConfigProvider);
      final DeliveryContext deliveryContext = DeliveryContext(
        policy: ref.read(devicePolicyProvider),
        rules: umpiringRulesFor(live.bundle.rules, config),
        batsmanHeightM: batsmanHeightMetres(
          matchPlayer: live.bundle.matchPlayerById(striker),
          player: live.bundle.playerById(striker),
        ),
        wicket: wicketTargetFrom(wicket),
        readiness: ScanReadiness.fromConfidence(wicket.finalConfidence),
        // The simulator's pitch is invented, so its flight length may be too.
        assumedFlightDistanceM: 15,
      );
      final DeliveryAnalysis result = await engine.simulateDelivery(
        kind: kind,
        context: deliveryContext,
        cancel: _cancel,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _analysis = result.wasCancelled ? null : result;
        _analysing = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _analysing = false);
      showMessage(context, friendlyError(error));
    }
  }

  // ---- Building ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<MatchBundle?> value = ref.watch(matchBundleProvider(widget.matchId));
    final MatchBundle? bundle = value.valueOrNull;
    final Innings? innings = bundle?.currentInnings;
    LiveBoard? openBoard;
    if (bundle != null && innings != null && !bundle.match.isFinished && !innings.isClosed) {
      openBoard = LiveBoard.from(bundle, innings);
    }
    final LiveBoard? board = openBoard;
    // Watched here (not in the helper methods) because `ref.watch` is only allowed in `build`.
    final CvEngine engine = ref.watch(cvEngineProvider);
    _ball = ref.watch(ballKindProvider).valueOrNull ?? ball_kind.BallKind.cricketBall;
    _distanceFeet = ref.watch(cameraDistanceFeetProvider(widget.matchId)).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live scoring'),
        actions: <Widget>[
          if (board != null) ...<Widget>[
            IconButton(
              tooltip: 'Undo the last ball',
              icon: const Icon(Icons.undo),
              onPressed:
                  board.hasActiveBall && !_busy && !_analysing ? () => unawaited(_undo()) : null,
            ),
            PopupMenuButton<_ScoringMenu>(
              tooltip: 'More',
              onSelected: (_ScoringMenu item) {
                if (item == _ScoringMenu.endInnings) {
                  unawaited(_confirmEndInnings());
                }
              },
              itemBuilder: (BuildContext _) => const <PopupMenuEntry<_ScoringMenu>>[
                PopupMenuItem<_ScoringMenu>(
                  value: _ScoringMenu.endInnings,
                  child: Text('End this innings'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: AsyncBody<MatchBundle?>(
        value: value,
        onRetry: () => ref.invalidate(matchBundleProvider(widget.matchId)),
        builder: (BuildContext context, MatchBundle? data) => _buildBody(context, data, engine),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MatchBundle? bundle, CvEngine engine) {
    if (bundle == null) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'Match not found',
        actionLabel: 'Go back',
        onAction: _leave,
      );
    }
    if (bundle.match.isFinished) {
      return EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'This match has ended',
        message: 'You can still read the full scorecard.',
        actionLabel: 'Open the scorecard',
        onAction: () => context.pushReplacement(Routes.scorecard(bundle.match.id)),
      );
    }
    final Innings? innings = bundle.currentInnings;
    if (innings == null) {
      return EmptyState(
        icon: Icons.play_circle_outline,
        title: 'The innings has not started',
        message: 'Start it from the match page, then come back to score.',
        actionLabel: 'Back to the match',
        onAction: _leave,
      );
    }
    if (innings.isClosed) {
      return EmptyState(
        icon: Icons.flag_outlined,
        title: 'This innings has ended',
        message: 'Go back to the match page to start the next innings or finish the match.',
        actionLabel: 'Back to the match',
        onAction: _leave,
      );
    }
    return _buildScoring(bundle, LiveBoard.from(bundle, innings), engine);
  }

  Widget _buildScoring(MatchBundle bundle, LiveBoard board, CvEngine engine) {
    final LiveReadiness readiness = board.readiness(_choices);
    final InningsProgress progress = board.progress;
    final InningsEndReason? endReason = progress.endReason;
    final bool ended = progress.shouldClose;
    final bool padEnabled = readiness.canScore && !ended && !_busy && !_analysing;

    final List<Widget> children = <Widget>[
      ScoreboardCard(board: board),
      const SizedBox(height: AppSpacing.md),
    ];

    if (ended && endReason != null) {
      children.addAll(<Widget>[
        MessageBanner(
          kind: BannerKind.success,
          title: endReason.label,
          message: 'The innings is over. End it to move on, or undo the last ball if it was a '
              'mistake.',
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_closeInnings()),
          child: const Text('End innings'),
        ),
        const SizedBox(height: AppSpacing.md),
      ]);
    }

    children.add(BattersCard(board: board, readiness: readiness));

    if (!ended) {
      if (readiness.missing.isNotEmpty) {
        children
          ..add(const SizedBox(height: AppSpacing.md))
          ..add(
            RequirementsCard(
              missing: readiness.missing,
              onChooseOpeners: () => unawaited(_chooseOpeners(board)),
              onChooseBatter: () => unawaited(_chooseIncomingBatter(board)),
              onChooseBowler: () => unawaited(_chooseBowler(board)),
            ),
          );
      }

      final List<Widget> changes = <Widget>[
        if (_choices.openerStrikerId != null && progress.setup == null)
          TextButton(
            onPressed: () => unawaited(_chooseOpeners(board)),
            child: const Text('Change openers'),
          ),
        if (_choices.incomingBatterId != null && progress.setup?.needsNewBatter == true)
          TextButton(
            onPressed: () => unawaited(_chooseIncomingBatter(board)),
            child: const Text('Change new batter'),
          ),
        if (_choices.bowlerId != null && progress.currentBowlerId == null)
          TextButton(
            onPressed: () => unawaited(_chooseBowler(board)),
            child: const Text('Change bowler'),
          ),
      ];
      if (changes.isNotEmpty) {
        children.add(Wrap(spacing: AppSpacing.sm, children: changes));
      }

      if (readiness.batterPairKnown && progress.setup?.strikeChoiceAllowed == true) {
        children.add(
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Swap who faces the next ball'),
            subtitle: const Text('After a run-out the batters may have crossed or not.'),
            value: _choices.endsSwapped,
            onChanged: (bool swapped) {
              setState(() => _choices = _choices.copyWith(endsSwapped: swapped));
            },
          ),
        );
      }
    }

    children
      ..add(const SizedBox(height: AppSpacing.lg))
      ..add(
        OverStrip(
          labels: board.overLabels,
          showingCompletedOver: progress.isShowingCompletedOver,
        ),
      );

    if (!ended) {
      final Widget? assistant = _assistantSection(bundle, readiness, engine);
      if (assistant != null) {
        children
          ..add(const SizedBox(height: AppSpacing.lg))
          ..add(assistant);
      }
    }

    return Column(
      children: <Widget>[
        Expanded(child: ScreenBody(children: children)),
        if (!ended)
          _PadBar(
            child: RunPad(
              enabled: padEnabled,
              onRuns: (int runs) => unawaited(_record(runs: runs)),
              onWicket: () => unawaited(_onWicket()),
              onExtra: (ExtraType type) => unawaited(_onExtra(type)),
            ),
          ),
      ],
    );
  }

  Widget? _assistantSection(MatchBundle bundle, LiveReadiness readiness, CvEngine engine) {
    if (!engine.isAvailable) {
      return null;
    }
    final DeliveryAnalysis? analysis = _analysis;
    final Widget? result = analysis == null
        ? null
        : UmpireSuggestionCard(
            analysis: analysis,
            onApply: (ExtraType type) => unawaited(_onExtra(type)),
            onDismiss: () {
              setState(() => _analysis = null);
              unawaited(_dropPendingReplay());
            },
            onReplay: _replayId == null ? null : _openReplay,
          );
    if (engine.mode == CvMode.live) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (result != null) ...<Widget>[result, const SizedBox(height: AppSpacing.md)],
          _liveCamera(bundle, readiness),
        ],
      );
    }
    if (_analysing) {
      return const _AnalysingCard();
    }
    if (result != null) {
      return result;
    }
    if (engine is SimulatedCvEngine) {
      return _SimulatorCard(
        hasWicket: bundle.activeWicket != null,
        enabled: readiness.canScore && !_busy,
        onSimulate: () => unawaited(_simulate()),
      );
    }
    return null;
  }

  /// The umpire camera, or an invitation to mark the stumps first.
  Widget _liveCamera(MatchBundle bundle, LiveReadiness readiness) {
    if (bundle.activeWicket == null) {
      return _MarkStumpsCard(onMark: () => unawaited(_markStumps()));
    }
    final LiveInputs inputs = liveInputsFor(
      bundle: bundle,
      strikerId: readiness.strikerId,
      policy: ref.read(devicePolicyProvider),
      config: ref.read(appConfigProvider),
      ballKind: _ball,
      cameraToBatterFeet: _distanceFeet,
    );
    return LiveCameraPanel(
      matchId: widget.matchId,
      inputs: inputs,
      onDelivery: _onDelivery,
      onMarkStumps: _markStumps,
    );
  }
}

/// The run pad, pinned to the bottom of the page so it is always under the thumb.
class _PadBar extends StatelessWidget {
  const _PadBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalysingCard extends StatelessWidget {
  const _AnalysingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Looking at the delivery...')),
          ],
        ),
      ),
    );
  }
}

/// Lets a tester try the assistant without a camera model. Only built for the simulated engine.
class _SimulatorCard extends StatelessWidget {
  const _SimulatorCard({
    required this.hasWicket,
    required this.enabled,
    required this.onSimulate,
  });

  final bool hasWicket;
  final bool enabled;
  final VoidCallback onSimulate;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.sports, color: AppColors.pitchGreen),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Umpire assistant',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SimulationBadge(),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hasWicket
                  ? 'Try the assistant on a made-up ball. Nothing is filmed.'
                  : 'To try the assistant, scan the wicket first from the match page.',
              style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
            ),
            if (hasWicket) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: enabled ? onSimulate : null,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Simulate a delivery'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown instead of the camera while the stumps have not been marked.
class _MarkStumpsCard extends StatelessWidget {
  const _MarkStumpsCard({required this.onMark});

  final VoidCallback onMark;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.videocam_outlined, color: AppColors.pitchGreen),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Umpire camera',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'To let the camera follow the ball, show it where the stumps are first.',
              style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onMark,
              icon: const Icon(Icons.crop_free),
              label: const Text('Mark the stumps'),
            ),
          ],
        ),
      ),
    );
  }
}
