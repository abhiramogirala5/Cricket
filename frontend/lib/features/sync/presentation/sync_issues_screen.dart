import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/dialogs.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/data/sync/sync_engine.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

/// What to tell the person about a change the server refused.
String describeFailure(OutboxEvent event) {
  final String? message = event.errorMessage?.trim();
  if (message != null && message.isNotEmpty) {
    return message;
  }
  return 'The server did not accept this change.';
}

/// Changes the server refused. Each one can be sent again or kept on this phone only.
class SyncIssuesScreen extends ConsumerWidget {
  const SyncIssuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyncEngine? engine = ref.watch(syncEngineProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync problems')),
      body: engine == null
          ? const EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Nothing to sync',
              message: 'This phone is not connected to an account.',
            )
          : AsyncBody<List<OutboxEvent>>(
              value: ref.watch(failedEventsProvider),
              onRetry: () => ref.invalidate(failedEventsProvider),
              builder: (BuildContext context, List<OutboxEvent> events) {
                if (events.isEmpty) {
                  return const EmptyState(
                    icon: Icons.cloud_done_outlined,
                    title: 'No problems',
                    message: 'Every change that can be sent has been sent.',
                  );
                }
                return ScreenBody(
                  children: <Widget>[
                    const MessageBanner(
                      kind: BannerKind.warning,
                      title: 'The server did not accept these changes',
                      message: 'Your matches are safe on this phone. You can try sending a change '
                          'again, or keep it on this phone only.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => _retryAll(context, engine),
                      child: const Text('Try all again'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    for (final OutboxEvent event in events) ...<Widget>[
                      _FailedEventCard(
                        event: event,
                        onRetry: () => _retry(context, engine, event),
                        onKeepLocal: () => _keepLocal(context, engine, event),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Future<void> _retryAll(BuildContext context, SyncEngine engine) async {
    try {
      await engine.retryAllFailed();
    } on Object catch (error) {
      if (context.mounted) {
        showMessage(context, friendlyError(error));
      }
    }
  }

  Future<void> _retry(BuildContext context, SyncEngine engine, OutboxEvent event) async {
    try {
      await engine.retryEvent(event.eventId);
    } on Object catch (error) {
      if (context.mounted) {
        showMessage(context, friendlyError(error));
      }
    }
  }

  Future<void> _keepLocal(BuildContext context, SyncEngine engine, OutboxEvent event) async {
    final bool confirmed = await confirmAction(
      context,
      title: 'Keep on this phone only?',
      message: 'This change will stay on this phone but will never be sent to your account.',
      confirmLabel: 'Keep on phone',
    );
    if (!confirmed) {
      return;
    }
    try {
      await engine.discardEvent(event.eventId);
    } on Object catch (error) {
      if (context.mounted) {
        showMessage(context, friendlyError(error));
      }
    }
  }
}

class _FailedEventCard extends StatelessWidget {
  const _FailedEventCard({
    required this.event,
    required this.onRetry,
    required this.onKeepLocal,
  });

  final OutboxEvent event;
  final VoidCallback onRetry;
  final VoidCallback onKeepLocal;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.error_outline, color: AppColors.ballRed, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    event.entityType.label,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(describeFailure(event), style: text.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextButton(onPressed: onKeepLocal, child: const Text('Keep on phone')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
