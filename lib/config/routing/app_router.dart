import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/logging/talker_provider.dart';
import 'system_modules/system_routes.dart';
import '../../features/auth/application/auth_controller.dart';
import 'app_navigation_config.dart';
import 'guards/guard_context.dart';
import 'navigation/navigation_service.dart';
import 'observers/app_route_observer.dart';
import 'redirect/redirect_policy.dart';
import 'route_params.dart';
import 'router_refresh.dart';
import 'routing_providers.dart';
import 'shells/main_shell.dart';

part 'app_router.g.dart';

/// Anything given this key renders above the shell chrome.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Built exactly once for the app's lifetime. A new GoRouter resets the stack
/// and, on web, the URL - so this reads, never watches, and reacts to auth
/// changes through `refreshListenable`.
///
/// Deliberately thin: routes come from feature modules, access rules from the
/// guards on each spec, the decision from the pure [RedirectPolicy]. This file
/// does not grow as the app does.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final navigation = ref.read(appNavigationProvider);
  final registry = ref.read(routeRegistryProvider);
  final talker = ref.read(talkerProvider);

  final refresh = RouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  const policy = RedirectPolicy();
  // One observer instance per navigator - see AppRouteObserver's note on why
  // sharing one trips `observer.navigator == null`.
  AppRouteObserver newObserver(String label) => AppRouteObserver(talker, registry: registry, label: label);

  // Synchronous on purpose: it runs on every navigation including the first
  // frame, and anything async shows up as a flicker.
  String? onRedirect(BuildContext context, GoRouterState state) => policy(
    GuardContext(
      auth: ref.read(authControllerProvider),
      uri: state.uri,
      matchedLocation: state.matchedLocation,
      route: registry.resolve(state),
      homeFor: navigation.homeFor,
    ),
  );

  // Preserves the URL the user actually typed so /404 can show it.
  void onException(BuildContext context, GoRouterState state, GoRouter router) {
    talker.warning('[route] unmatched ${state.uri}');
    router.go(SystemRoutes.notFound.withQuery({RouteQuery.attempted: state.uri.toString()}));
  }

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: SystemRoutes.login.path,
    debugLogDiagnostics: kDebugMode,
    restorationScopeId: 'cash_counter_pos_routes',
    refreshListenable: refresh,
    // If this is ever hit, two rules contradict each other. Keeping it low
    // turns a silent infinite loop into a loud assertion.
    redirectLimit: 8,
    redirect: onRedirect,
    onException: onException,
    observers: [newObserver('root')],
    routes: [
      navigation.buildShell(
        rootNavigatorKey: rootNavigatorKey,
        observerFactory: (branch) => [newObserver(branch.destination.spec.name)],
        shellBuilder: (context, state, shell) => MainShell(navigationShell: shell),
      ),
      for (final module in AppModules.topLevel) ...module.routes(rootNavigatorKey),
    ],
  );

  // Lets Dio interceptors, notification handlers and the deep-link handler
  // navigate without a BuildContext.
  NavigationService.instance.attach(router, registry);
  ref.onDispose(() {
    NavigationService.instance.detach();
    router.dispose();
  });

  return router;
}
