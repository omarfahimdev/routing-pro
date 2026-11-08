import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/auth/application/auth_controller.dart';
import '../navigation/navigation_extensions.dart';
import '../routing_providers.dart';
import '../system_modules/system_routes.dart';

/// Shown while the session is read from disk. The redirect policy moves the
/// user on as soon as bootstrapping finishes.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Shared layout for the system pages.
class _SystemPage extends StatelessWidget {
  const _SystemPage({required this.icon, required this.headline, this.detail, this.actions = const <Widget>[]});

  final IconData icon;
  final String headline;
  final String? detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text(headline, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(detail!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: actions),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotFoundScreen extends ConsumerWidget {
  const NotFoundScreen({this.attempted, super.key});

  final String? attempted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider.select((state) => state.sessionOrNull));

    return _SystemPage(
      icon: Icons.explore_off_outlined,
      headline: 'That page does not exist',
      detail: attempted,
      actions: [
        FilledButton(
          onPressed: () =>
              context.go(session == null ? SystemRoutes.login.path : ref.read(appNavigationProvider).homeFor(session)),
          child: const Text('Take me home'),
        ),
      ],
    );
  }
}

class ForbiddenScreen extends ConsumerWidget {
  const ForbiddenScreen({this.attempted, super.key});

  final String? attempted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider.select((state) => state.sessionOrNull));

    return _SystemPage(
      icon: Icons.lock_outline,
      headline: 'Your role does not have access to this page',
      detail: attempted,
      actions: [
        OutlinedButton(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          child: const Text('Sign in as someone else'),
        ),
        if (session != null)
          FilledButton(
            onPressed: () => context.go(ref.read(appNavigationProvider).homeFor(session)),
            child: const Text('Go back'),
          ),
      ],
    );
  }
}

class AppErrorScreen extends StatelessWidget {
  const AppErrorScreen({this.message, this.onRetry, super.key});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => _SystemPage(
    icon: Icons.error_outline,
    headline: 'Something went wrong',
    detail: message,
    actions: [
      if (onRetry != null) FilledButton(onPressed: onRetry, child: const Text('Try again')),
      OutlinedButton(onPressed: () => context.goTo(SystemRoutes.splash), child: const Text('Restart')),
    ],
  );
}

/// PIN lock.
///
/// Note there is no navigation call: unlocking flips auth state, the refresh
/// notifier fires, and the redirect policy reads `?from=` and moves the user.
class LockScreen extends ConsumerWidget {
  const LockScreen({this.returnTo, super.key});

  final String? returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider.select((state) => state.sessionOrNull));

    return _SystemPage(
      icon: Icons.lock_clock_outlined,
      headline: session == null ? 'Terminal locked' : 'Welcome back, ${session.displayName}',
      detail: returnTo == null ? null : 'Returning to $returnTo',
      actions: [
        FilledButton(onPressed: ref.read(authControllerProvider.notifier).unlock, child: const Text('Unlock with PIN')),
        TextButton(onPressed: () => ref.read(authControllerProvider.notifier).signOut(), child: const Text('Sign out')),
      ],
    );
  }
}

/// Shift gate, reached whenever a guard chain includes `OpenShiftGuard` and the
/// session has no open shift. [returnTo] arrives already sanitised.
class OpenShiftScreen extends ConsumerWidget {
  const OpenShiftScreen({this.returnTo, super.key});

  final String? returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SystemPage(
    icon: Icons.point_of_sale_outlined,
    headline: 'Open the register to start selling',
    detail: 'Count your float first.',
    actions: [
      FilledButton(
        onPressed: () async {
          // TODO(shift): await ref.read(shiftControllerProvider.notifier).open(...)
          // if (context.mounted) context.go(returnTo ?? TerminalRoutes.root.path);
        },
        child: const Text('Open shift'),
      ),
    ],
  );
}
