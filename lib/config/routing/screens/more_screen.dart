import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/application/auth_controller.dart';
import '../system_modules/more_module.dart';
import '../navigation/navigation_extensions.dart';
import '../routing_providers.dart';

/// The overflow tab: every drawer destination the session may see that is not
/// already a tab. Same list, same permission filter as the rail and drawer.
///
/// It also hosts the session controls, because lock and sign-out are the two
/// actions that let you watch `RedirectPolicy` work: locking parks you on
/// `/lock?from=<here>` and unlocking returns you to exactly this screen.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.watch(appNavigationProvider);
    final session = ref.watch(authControllerProvider.select((state) => state.sessionOrNull));
    if (session == null) return const SizedBox.shrink();

    final tabs = navigation.tabs;
    final items = navigation.visibleDrawer(session).where((d) => !tabs.contains(d)).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          // ---- who is signed in, and with what
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(session.displayName),
            subtitle: Text(
              '${session.roleNames.join(', ')}  ·  ${session.permissionKeys.length} permissions',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const Divider(),

          // ---- destinations this session may see but has no tab for
          for (final destination in items)
            ListTile(
              leading: Icon(destination.icon),
              title: Text(destination.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.goTo(destination.spec),
            ),
          if (items.isEmpty)
            ListTile(
              enabled: false,
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('No extra destinations'),
              subtitle: Text('This role sees everything it may see as a tab.', style: theme.textTheme.bodySmall),
            ),

          const Divider(),

          // ---- dev tools
          ListTile(
            leading: const Icon(Icons.alt_route),
            title: Text(MoreModule.inspector.title),
            subtitle: Text('Every route, its guard chain and this session\'s verdict', style: theme.textTheme.bodySmall),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goTo(MoreModule.inspector),
          ),

          const Divider(),

          // ---- session lifecycle. Neither of these navigates: they change
          // auth state and the redirect policy reacts.
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('Lock terminal'),
            subtitle: Text('Parks you on /lock?from=/more - unlocking comes back here', style: theme.textTheme.bodySmall),
            onTap: ref.read(authControllerProvider.notifier).lock,
          ),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sign out', style: TextStyle(color: theme.colorScheme.error)),
            subtitle: Text('Sign in again as another role to see the nav change', style: theme.textTheme.bodySmall),
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}
