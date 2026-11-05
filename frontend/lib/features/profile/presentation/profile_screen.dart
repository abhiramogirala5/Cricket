import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/core/di/cv_providers.dart';
import 'package:gully_umpire/core/di/session_providers.dart';
import 'package:gully_umpire/core/widgets/dialogs.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/core/widgets/section_header.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/engine/cv_engine.dart';
import 'package:gully_umpire/data/sync/restore_service.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';
import 'package:gully_umpire/features/profile/presentation/delete_account_dialog.dart';
import 'package:gully_umpire/features/profile/presentation/profile_edit_sheet.dart';
import 'package:gully_umpire/features/profile/profile_text.dart';
import 'package:gully_umpire/features/sync/presentation/sync_status_tile.dart';

/// The account: name and contact, saved players, sync, and the safe ways in and out.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;
  bool _restoring = false;

  Future<void> _edit(UserProfile user) async {
    final ProfileChanges? changes = await showProfileEditSheet(context, user: user);
    if (!mounted) {
      return;
    }
    if (changes == null || changes.isEmpty) {
      return;
    }
    await _run(() async {
      await ref.read(sessionControllerProvider.notifier).updateProfile(
            displayName: changes.displayName,
            phone: changes.phone,
            clearPhone: changes.clearPhone,
          );
      if (mounted) {
        showMessage(context, 'Profile saved.');
      }
    });
  }

  Future<void> _restore() async {
    await _run(() async {
      setState(() => _restoring = true);
      try {
        final RestoreReport report =
            await ref.read(sessionControllerProvider.notifier).restoreFromServer();
        if (mounted) {
          showMessage(context, describeRestore(report));
        }
      } finally {
        if (mounted) {
          setState(() => _restoring = false);
        }
      }
    });
  }

  Future<void> _signOut() async {
    final bool confirmed = await confirmAction(
      context,
      title: 'Sign out?',
      message: 'Anything still waiting is sent first. Your matches stay saved on this phone '
          'and are here again when you sign back in.',
      confirmLabel: 'Sign out',
    );
    if (!mounted) {
      return;
    }
    if (!confirmed) {
      return;
    }
    // The router takes the user to the sign-in page as soon as the session ends.
    await _run(() => ref.read(sessionControllerProvider.notifier).signOut());
  }

  Future<void> _deleteAccount() async {
    final bool deleted = await showDeleteAccountDialog(context);
    if (!mounted) {
      return;
    }
    if (deleted) {
      showMessage(context, 'Your account was deleted.');
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final UserProfile? user = ref.watch(currentUserProvider);
    final bool isLocal = ref.watch(isLocalModeProvider);
    final AppConfig config = ref.watch(appConfigProvider);
    final CvEngine engine = ref.watch(cvEngineProvider);
    final DevicePolicy policy = ref.watch(devicePolicyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ScreenBody(
        children: <Widget>[
          if (isLocal) const _LocalModeCard() else if (user != null) _AccountCard(user: user),
          if (user != null && !isLocal) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => unawaited(_edit(user)),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
          ],
          const SectionHeader('Your cricket'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_outlined, color: AppColors.pitchGreen),
              title: const Text('Saved players'),
              subtitle: const Text('Names, batting hand and height'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => unawaited(context.push(Routes.players)),
            ),
          ),
          const SectionHeader('Sync'),
          SyncStatusTile(
            onTap: isLocal ? null : () => unawaited(context.push(Routes.syncIssues)),
          ),
          if (!isLocal) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_download_outlined, color: AppColors.pitchGreen),
                title: const Text('Get my matches from the server'),
                subtitle: const Text('Useful on a new phone. Nothing on this phone is replaced.'),
                trailing: _restoring
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _busy ? null : () => unawaited(_restore()),
              ),
            ),
          ],
          const SectionHeader('About this app'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  _AboutRow(label: 'Version type', value: _environmentLabel(config.environment)),
                  _AboutRow(
                    label: 'This phone',
                    value: policy.profile.label,
                  ),
                  _AboutRow(
                    label: 'Umpire assistant',
                    value: switch (engine.mode) {
                      CvMode.live => 'Live camera',
                      CvMode.simulated => 'Simulated (test build)',
                      CvMode.scoreOnly => 'Camera not used, scoring only',
                    },
                  ),
                ],
              ),
            ),
          ),
          if (!isLocal && user != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => unawaited(_signOut()),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.ballRed),
              onPressed: _busy ? null : () => unawaited(_deleteAccount()),
              child: const Text('Delete my account'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Deleting removes your account and its matches from the server and this phone.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }

  static String _environmentLabel(AppEnvironment environment) {
    switch (environment) {
      case AppEnvironment.development:
        return 'Development';
      case AppEnvironment.staging:
        return 'Staging';
      case AppEnvironment.production:
        return 'Release';
    }
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? phone = user.phone;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.pitchGreen,
              foregroundColor: Colors.white,
              child: Text(
                user.initials,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                  ),
                  if (phone != null && phone.isNotEmpty)
                    Text(
                      phone,
                      style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalModeCard extends StatelessWidget {
  const _LocalModeCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.phone_android, color: AppColors.pitchGreen),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Saved on this phone',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'This build has no server set up, so there is no account. Your matches stay '
                    'on this phone only.',
                    style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.inkMuted)),
          ),
          Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
