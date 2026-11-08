import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/application/auth_controller.dart';
import '../../../features/auth/data/demo_sessions.dart';
import '../navigation/navigation_extensions.dart';
import '../system_modules/system_routes.dart';

/// ============================================================================
/// SIGN-IN.
///
/// THE RULE THIS SCREEN DEMONSTRATES: it changes auth state and does nothing
/// else. No `context.go`, no `pushTo`. `AuthController.signIn` writes the
/// session, `RouterRefreshNotifier` notices the state changed, go_router
/// re-runs `RedirectPolicy`, and the policy sends the user to `?from=` or to
/// `AppNavigation.homeFor(session)`.
///
/// Navigating from here instead is the classic bug: push `/dashboard` while
/// still unauthenticated and `AuthGuard` bounces you straight back to `/login`,
/// so the button looks dead.
///
/// The role picker is a stand-in for a real API (see `DemoRole`): switch roles
/// and watch the tab bar, the drawer and the guards change together.
/// ============================================================================
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({required this.onForgotPassword, super.key});

  final VoidCallback onForgotPassword;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  DemoRole _role = DemoRole.owner;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // The only call. Whatever happens next is the router's decision.
      await ref.read(authControllerProvider.notifier).signIn(_role.session(email: _email.text.trim()));
    } catch (error) {
      // Typically the secure-storage write failing on a fresh simulator.
      if (mounted) setState(() => _error = '$error');
    } finally {
      // The redirect usually disposes this screen first, hence the guard.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.storefront, size: 48),
        const SizedBox(height: 16),
        Text('Sign in', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: 24),

        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          decoration: InputDecoration(labelText: 'Email', hintText: '${_role.roleName}@demo.pos'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Password', hintText: 'anything - there is no API yet'),
        ),

        const SizedBox(height: 20),
        Text('Sign in as', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        SegmentedButton<DemoRole>(
          segments: [
            for (final role in DemoRole.values) ButtonSegment(value: role, label: Text(role.label)),
          ],
          selected: {_role},
          onSelectionChanged: _busy ? null : (selection) => setState(() => _role = selection.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 8),
        Text(
          '${_role.permissionKeys.length} permissions - a cashier sees fewer tabs and is '
          'bounced from /reports.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),

        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],

        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign in'),
        ),
        TextButton(onPressed: _busy ? null : widget.onForgotPassword, child: const Text('Forgot password?')),
      ],
    );
  }
}

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Reset password', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('We will e-mail a link to /reset-password/<token>.', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      TextButton(onPressed: () => context.goTo(SystemRoutes.login), child: const Text('Back to sign in')),
    ],
  );
}

/// Deep-link target from the reset e-mail. The token lives in the path, so a
/// cold browser load works with zero app state.
class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({required this.token, super.key});

  final String token;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Choose a new password', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      SelectableText('Token: $token'),
    ],
  );
}
