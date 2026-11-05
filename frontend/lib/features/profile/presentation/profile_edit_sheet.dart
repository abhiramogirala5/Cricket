import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';
import 'package:gully_umpire/features/auth/auth_validators.dart';

/// The changes made in the profile sheet. A `null` field was not changed.
final class ProfileChanges {
  const ProfileChanges({this.displayName, this.phone, this.clearPhone = false});

  final String? displayName;
  final String? phone;
  final bool clearPhone;

  bool get isEmpty => displayName == null && phone == null && !clearPhone;
}

/// Edits the name and the phone number of the account. Returns `null` when dismissed, and an
/// empty [ProfileChanges] when nothing was changed.
Future<ProfileChanges?> showProfileEditSheet(BuildContext context, {required UserProfile user}) {
  return showModalBottomSheet<ProfileChanges>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: _ProfileEditSheet(user: user),
    ),
  );
}

class _ProfileEditSheet extends StatefulWidget {
  const _ProfileEditSheet({required this.user});

  final UserProfile user;

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.user.displayName);
  late final TextEditingController _phone = TextEditingController(text: widget.user.phone ?? '');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final String name = _name.text.trim();
    final String phone = _phone.text.trim();
    final String? oldPhone = widget.user.phone;
    Navigator.of(context).pop(
      ProfileChanges(
        displayName: name == widget.user.displayName ? null : name,
        phone: phone.isNotEmpty && phone != oldPhone ? phone : null,
        clearPhone: phone.isEmpty && oldPhone != null && oldPhone.isNotEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Edit your profile',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: validateDisplayName,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                validator: validateOptionalPhone,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(onPressed: _save, child: const Text('Save changes')),
            ],
          ),
        ),
      ),
    );
  }
}
