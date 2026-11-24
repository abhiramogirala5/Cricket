import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Records who called, what the coin showed, and what the winner chose with an authentic
/// 3D animated cricket coin toss.
class TossScreen extends ConsumerWidget {
  const TossScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match Toss')),
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

class _TossFormState extends ConsumerState<_TossForm> with SingleTickerProviderStateMixin {
  late String _callingTeamId;
  late TossSide _call;
  TossSide? _result;
  late TossDecision _decision;
  bool _busy = false;
  String? _error;

  // ---- 3D Flip Animation ----
  late final AnimationController _flipController;
  late final Animation<double> _flipCurved;
  double _currentRotation = 0.0;
  double _startRotation = 0.0;
  double _targetRotation = 0.0;
  TossSide? _pendingResult;
  int _lastHalfTurn = 0;
  bool _showManualOverride = false;

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
      _currentRotation = toss.result == TossSide.heads ? 0.0 : pi;
    } else {
      _callingTeamId = _bundle.teamA.id;
      _call = TossSide.heads;
      _decision = TossDecision.bat;
      _currentRotation = 0.0;
    }

    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _flipCurved = CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeOutCubic,
    );

    _flipController.addListener(_onFlipTick);
    _flipController.addStatusListener(_onFlipStatus);
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _onFlipTick() {
    final double t = _flipCurved.value;
    final double rot = ui.lerpDouble(_startRotation, _targetRotation, t) ?? _targetRotation;
    final int halfTurn = (rot / pi).floor();
    if (halfTurn != _lastHalfTurn) {
      _lastHalfTurn = halfTurn;
      unawaited(HapticFeedback.selectionClick());
    }
    setState(() {
      _currentRotation = rot;
    });
  }

  void _onFlipStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _result = _pendingResult;
        _currentRotation = _targetRotation % (2 * pi);
      });
    }
  }

  bool get _flipping => _flipController.isAnimating;

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

  void _flipCoin([TossSide? explicitOutcome]) {
    if (_flipping || _busy) {
      return;
    }
    final TossSide outcome = explicitOutcome ?? (Random().nextBool() ? TossSide.heads : TossSide.tails);
    unawaited(HapticFeedback.mediumImpact());

    // Spin at least 5 full rotations (10 half-turns)
    const int baseFullRotations = 5;
    final double currentMod = _currentRotation % (2 * pi);
    final double targetMod = outcome == TossSide.heads ? 0.0 : pi;
    double delta = targetMod - currentMod;
    if (delta <= 0) {
      delta += 2 * pi;
    }
    final double targetAngle = _currentRotation + (baseFullRotations * 2 * pi) + delta;

    setState(() {
      _result = null;
      _pendingResult = outcome;
      _startRotation = _currentRotation;
      _targetRotation = targetAngle;
      _lastHalfTurn = (_startRotation / pi).floor();
    });

    _flipController.reset();
    _flipController.forward();
  }

  void _setManualResult(TossSide side) {
    if (_flipping || _busy) {
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _result = side;
      _pendingResult = side;
      _currentRotation = side == TossSide.heads ? 0.0 : pi;
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
        // Step 1: Who Calls & Their Call
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '1. Who calls the toss?',
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TeamPickerChip(
                        teamName: _bundle.teamA.name,
                        selected: _callingTeamId == _bundle.teamA.id,
                        disabled: _flipping,
                        onTap: () => setState(() => _callingTeamId = _bundle.teamA.id),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _TeamPickerChip(
                        teamName: _bundle.teamB.name,
                        selected: _callingTeamId == _bundle.teamB.id,
                        disabled: _flipping,
                        onTap: () => setState(() => _callingTeamId = _bundle.teamB.id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '2. The call in the air',
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _CallChoiceCard(
                        title: 'HEADS',
                        subtitle: '🦁 Lion Crest',
                        selected: _call == TossSide.heads,
                        disabled: _flipping,
                        onTap: () => setState(() => _call = TossSide.heads),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _CallChoiceCard(
                        title: 'TAILS',
                        subtitle: '🏏 Stumps & Bat',
                        selected: _call == TossSide.tails,
                        disabled: _flipping,
                        onTap: () => setState(() => _call = TossSide.tails),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Step 2: Interactive 3D Coin Toss Arena
        Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 1.1,
                colors: <Color>[
                  AppColors.grassTint.withValues(alpha: 0.6),
                  Colors.white,
                ],
              ),
            ),
            child: Column(
              children: <Widget>[
                Text(
                  _flipping
                      ? 'FLIPPING IN THE AIR…'
                      : (result == null ? 'TAP COIN TO FLIP' : 'COIN LANDED ON ${result.label.toUpperCase()}!'),
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: _flipping ? AppColors.creaseAmberInk : AppColors.pitchGreenDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // 3D Coin with height trajectory and dynamic shadow
                _CricketCoin3D(
                  rotationAngle: _currentRotation,
                  flipProgress: _flipCurved.value,
                  isFlipping: _flipping,
                  onTap: _flipping ? null : () => _flipCoin(),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.pitchGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _flipping ? null : () => _flipCoin(),
                    icon: _flipping
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.casino_outlined, size: 22),
                    label: Text(
                      _flipping ? 'Coin is in the air…' : (result == null ? 'FLIP COIN' : 'FLIP AGAIN'),
                      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Discreet toggle for manual coin entry (if real coin was tossed)
                TextButton(
                  onPressed: () => setState(() => _showManualOverride = !_showManualOverride),
                  child: Text(
                    _showManualOverride ? 'Hide manual outcome options' : 'Tossed a real coin? Select outcome directly',
                    style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
                  ),
                ),
                if (_showManualOverride) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: <Widget>[
                      ChoiceChip(
                        avatar: const Icon(Icons.circle, size: 14, color: AppColors.creaseAmber),
                        label: const Text('Real coin: Heads'),
                        selected: result == TossSide.heads && !_flipping,
                        onSelected: _flipping ? null : (_) => _setManualResult(TossSide.heads),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.circle, size: 14, color: AppColors.pitchGreen),
                        label: const Text('Real coin: Tails'),
                        selected: result == TossSide.tails && !_flipping,
                        onSelected: _flipping ? null : (_) => _setManualResult(TossSide.tails),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // Step 3: Winner Announcement & Bat/Bowl Decision
        if (winner != null && !_flipping) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.grassTint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.pitchGreen.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text('🏆', style: TextStyle(fontSize: 26)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${_bundle.teamName(winner)} won the toss!',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.pitchGreenDark,
                            ),
                          ),
                          Text(
                            winner == _callingTeamId
                                ? 'Called ${result?.label} correctly.'
                                : 'Coin landed ${result?.label}.',
                            style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'What do they choose?',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _DecisionOptionCard(
                        title: 'BAT FIRST',
                        icon: Icons.sports_cricket,
                        selected: _decision == TossDecision.bat,
                        onTap: () => setState(() => _decision = TossDecision.bat),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _DecisionOptionCard(
                        title: 'BOWL FIRST',
                        icon: Icons.sports_baseball,
                        selected: _decision == TossDecision.bowl,
                        onTap: () => setState(() => _decision = TossDecision.bowl),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${_bundle.teamName(winner)} will ${_decision.label} first in the 1st innings.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.pitchGreenDark,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          MessageBanner(message: _error!, kind: BannerKind.error),
        ],

        const SizedBox(height: AppSpacing.xl),

        // Final Save CTA
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: (_busy || winner == null || _flipping) ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Save Toss & Continue', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

// ==============================================================================================
// 3D Animated Cricket Coin & Face Renderers
// ==============================================================================================

class _CricketCoin3D extends StatelessWidget {
  const _CricketCoin3D({
    required this.rotationAngle,
    required this.flipProgress,
    required this.isFlipping,
    this.onTap,
  });

  final double rotationAngle;
  final double flipProgress;
  final bool isFlipping;
  final VoidCallback? onTap;

  static const double _coinSize = 136.0;

  @override
  Widget build(BuildContext context) {
    // Height trajectory: climbs 80px into the air during flip
    final double trajectoryY = isFlipping ? -sin(flipProgress * pi) * 85.0 : 0.0;
    // Scale trajectory: enlarges slightly at apex
    final double scale = isFlipping ? 1.0 + sin(flipProgress * pi) * 0.16 : 1.0;
    // Shadow properties: spreads out and dims as coin climbs
    final double shadowSpread = isFlipping ? 1.0 + sin(flipProgress * pi) * 0.7 : 1.0;
    final double shadowOpacity = isFlipping ? 0.35 - sin(flipProgress * pi) * 0.20 : 0.35;

    // Which face is towards the camera
    final double cosAngle = cos(rotationAngle);
    final bool isHeads = cosAngle >= 0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _coinSize * 1.5,
        height: _coinSize * 1.8,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: <Widget>[
            // Ground drop shadow
            Positioned(
              bottom: 12,
              child: Container(
                width: _coinSize * 0.85 * shadowSpread,
                height: 18 * shadowSpread,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(_coinSize * 0.85, 18)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: shadowOpacity),
                      blurRadius: 16 * shadowSpread,
                      spreadRadius: 2 * shadowSpread,
                    ),
                  ],
                ),
              ),
            ),

            // Flipping Coin with 3D perspective
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translate(0.0, trajectoryY)
                ..scale(scale)
                ..setEntry(3, 2, 0.0018)
                ..rotateX(rotationAngle),
              child: isHeads
                  ? _CoinFace(side: TossSide.heads, size: _coinSize)
                  : Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateX(pi),
                      child: _CoinFace(side: TossSide.tails, size: _coinSize),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinFace extends StatelessWidget {
  const _CoinFace({required this.side, required this.size});

  final TossSide side;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool isHeads = side == TossSide.heads;

    // Metallic gold palette
    final List<Color> rimColors = isHeads
        ? const <Color>[
            Color(0xFFFFE082),
            Color(0xFFFFB300),
            Color(0xFFFFA000),
            Color(0xFFFFD54F),
            Color(0xFFFF8F00),
          ]
        : const <Color>[
            Color(0xFFFFD54F),
            Color(0xFFFFA000),
            Color(0xFFE65100),
            Color(0xFFFFB74D),
            Color(0xFFBF360C),
          ];

    final List<Color> faceColors = isHeads
        ? const <Color>[
            Color(0xFFFFECB3),
            Color(0xFFFFCA28),
            Color(0xFFFFB300),
          ]
        : const <Color>[
            Color(0xFFFFE082),
            Color(0xFFFFB74D),
            Color(0xFFF57C00),
          ];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: rimColors,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5.5),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFFFF8E1).withValues(alpha: 0.8),
              width: 2.2,
            ),
            gradient: RadialGradient(
              center: const Alignment(-0.2, -0.2),
              radius: 0.9,
              colors: faceColors,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Beveled inner decorative ring
              Container(
                margin: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (isHeads ? const Color(0xFFD48800) : const Color(0xFFBF360C)).withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
              ),

              // Coin Insignia & Label
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    isHeads ? '★ GULLY UMPIRE ★' : '★ EST. 2026 ★',
                    style: TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: isHeads ? const Color(0xFF6D4C41) : const Color(0xFF4E342E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    isHeads ? Icons.sports_cricket : Icons.sports_baseball,
                    size: 38,
                    color: isHeads ? const Color(0xFF4E342E) : const Color(0xFF3E2723),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isHeads ? 'HEADS' : 'TAILS',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: isHeads ? const Color(0xFF3E2723) : const Color(0xFF2E1C0C),
                      shadows: const <Shadow>[
                        Shadow(color: Color(0x66FFFFFF), offset: Offset(0, 1), blurRadius: 1),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================================
// Custom Selectors & Decision Cards
// ==============================================================================================

class _TeamPickerChip extends StatelessWidget {
  const _TeamPickerChip({
    required this.teamName,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String teamName;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.pitchGreen : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.pitchGreen : AppColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            Text(
              teamName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.ink,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              selected ? 'Calling' : 'Tap to call',
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white.withValues(alpha: 0.85) : AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallChoiceCard extends StatelessWidget {
  const _CallChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.creaseAmberTint : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.creaseAmber : AppColors.outline,
            width: selected ? 2.2 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.8,
                color: selected ? AppColors.creaseAmberInk : AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.creaseAmberInk : AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionOptionCard extends StatelessWidget {
  const _DecisionOptionCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.pitchGreen : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.pitchGreen : AppColors.outline,
            width: selected ? 2.5 : 1.2,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.pitchGreen.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: <Widget>[
            Icon(
              icon,
              size: 26,
              color: selected ? Colors.white : AppColors.pitchGreen,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0.8,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
