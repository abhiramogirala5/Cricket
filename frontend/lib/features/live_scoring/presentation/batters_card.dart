import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/features/live_scoring/live_board.dart';

/// Who is batting and who is bowling right now.
class BattersCard extends StatelessWidget {
  const BattersCard({super.key, required this.board, required this.readiness});

  final LiveBoard board;
  final LiveReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? strikerId = readiness.strikerId;
    final String? nonStrikerId = readiness.nonStrikerId;
    final String? bowlerId = readiness.bowlerId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _BatterRow(board: board, playerId: strikerId, onStrike: true),
            const SizedBox(height: AppSpacing.sm),
            _BatterRow(board: board, playerId: nonStrikerId, onStrike: false),
            const Divider(height: AppSpacing.xl),
            Row(
              children: <Widget>[
                const Icon(Icons.sports_baseball_outlined, size: 20, color: AppColors.ballRed),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    bowlerId == null ? 'Bowler not chosen' : board.bundle.playerName(bowlerId),
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (bowlerId != null)
                  Text(
                    bowlerFigures(board.bowlerLine(bowlerId)),
                    style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatterRow extends StatelessWidget {
  const _BatterRow({required this.board, required this.playerId, required this.onStrike});

  final LiveBoard board;
  final String? playerId;
  final bool onStrike;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? id = playerId;
    final BatterLine? line = id == null ? null : board.batterLine(id);
    return Row(
      children: <Widget>[
        Icon(
          onStrike ? Icons.sports_cricket : Icons.person_outline,
          size: 20,
          color: onStrike ? AppColors.pitchGreen : AppColors.inkMuted,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            id == null ? 'Batter not chosen' : '${board.bundle.playerName(id)}${onStrike ? ' *' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall?.copyWith(
              fontWeight: onStrike ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        if (line != null)
          Text(
            '${line.runs} (${line.balls})',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
      ],
    );
  }
}
