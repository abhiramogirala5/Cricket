import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/data/sync/sync_state.dart';
import 'package:gully_umpire/features/sync/sync_summary.dart';

/// A card that says whether the matches on this phone have reached the account.
class SyncStatusTile extends ConsumerWidget {
  const SyncStatusTile({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isLocal = ref.watch(appConfigProvider).isLocalMode;
    final SyncState state = ref.watch(syncStateProvider).valueOrNull ?? SyncState.initial;
    final SyncSummary summary = describeSync(state, isLocalMode: isLocal);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: <Widget>[
              _SeverityIcon(summary.severity, busy: state.isSyncing),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      summary.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.inkMuted,
                          ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeverityIcon extends StatelessWidget {
  const _SeverityIcon(this.severity, {required this.busy});

  final SyncSeverity severity;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    }
    switch (severity) {
      case SyncSeverity.calm:
        return const Icon(Icons.cloud_done_outlined, color: AppColors.pitchGreen, size: 28);
      case SyncSeverity.working:
        return const Icon(Icons.cloud_upload_outlined, color: AppColors.skyBlue, size: 28);
      case SyncSeverity.attention:
        return const Icon(Icons.cloud_off_outlined, color: AppColors.creaseAmber, size: 28);
      case SyncSeverity.problem:
        return const Icon(Icons.error_outline, color: AppColors.ballRed, size: 28);
    }
  }
}
