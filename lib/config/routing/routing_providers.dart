import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_navigation.dart';
import 'app_navigation_config.dart';
import 'deep_links/deep_link_handler.dart';
import 'route_registry.dart';

part 'routing_providers.g.dart';

/// Tabs, drawer and landing rules. Immutable for the app's lifetime.
///
/// `keepAlive` matters: the shell's branch navigator keys live inside this
/// object, and recreating them would reset every tab's navigation stack.
@Riverpod(keepAlive: true)
AppNavigation appNavigation(Ref ref) => buildAppNavigation();

/// Lookup + validation over every module's specs. Throws at startup on a
/// duplicate path/name or an orphaned child.
@Riverpod(keepAlive: true)
RouteRegistry routeRegistry(Ref ref) {
  final navigation = ref.watch(appNavigationProvider);
  return RouteRegistry.of([...AppModules.topLevel, for (final branch in navigation.branches) branch.module]);
}

/// Validates and applies externally supplied links (notifications, QR codes,
/// custom schemes).
@Riverpod(keepAlive: true)
DeepLinkHandler deepLinkHandler(Ref ref) => DeepLinkHandler(registry: ref.watch(routeRegistryProvider));
