import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/session_providers.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/features/auth/auth_validators.dart';
import 'package:gully_umpire/features/auth/presentation/auth_scaffold.dart';

/// Sign in with email and password. With [reauth] the user is already inside the app and only
/// needs to sign in again because the session ended; unsent changes are kept and sent afterwards.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.reauth = false});

  final bool reauth;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.reauth) {
      _email.text = ref.read(currentUserProvider)?.email ?? '';
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).login(
            email: _email.text,
            password: _password.text,
          );
      if (!mounted) {
        return;
      }
      if (widget.reauth) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(Routes.home);
        }
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
    return AuthScaffold(
      title: widget.reauth ? 'Sign in again' : 'Welcome back',
      subtitle: widget.reauth
          ? 'Your matches are safe on this phone. Sign in to send them to your account.'
          : 'Sign in to score matches and keep them safe.',
      showBack: widget.reauth,
      children: <Widget>[
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.email],
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: validateEmail,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.password],
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: validateLoginPassword,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          MessageBanner(message: _error!, kind: BannerKind.error),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Sign in'),
        ),
        if (!widget.reauth) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _busy ? null : () => context.go(Routes.signUp),
            child: const Text('New here? Create an account'),
          ),
        ],
      ],
    );
  }
}
