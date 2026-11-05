import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/session_providers.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';

/// Shown while the app opens the saved account. If that fails the user can try again.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Object?> session = ref.watch(sessionControllerProvider);
    final Object? error = session.hasError ? session.error : null;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: AppColors.pitchGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sports_cricket, size: 46, color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Gully Umpire',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (error == null)
                const CircularProgressIndicator()
              else ...<Widget>[
                Text(
                  friendlyError(error),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () => ref.read(sessionControllerProvider.notifier).retryStart(),
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
