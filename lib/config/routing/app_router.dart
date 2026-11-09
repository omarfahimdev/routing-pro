import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/logging/talker_provider.dart';
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
import 'system_modules/system_routes.dart';

part 'app_router.g.dart';

/// The key of the root navigator.
///
/// A route given this key as its `parentNavigatorKey` renders above the shell
/// chrome (navigation bar or rail), which is how full-screen flows such as
/// checkout and refund cover it.
///
/// ```dart
/// GoRoute(
///   path: 'refund',
///   parentNavigatorKey: rootNavigatorKey,
///   builder: (context, state) => const RefundScreen(),
/// ),
/// ```
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The application's [GoRouter], built once for the lifetime of the app.
///
/// A new [GoRouter] resets the navigation stack and, on web, the URL, so this
/// provider is `keepAlive` and must never rebuild. It therefore only ever
/// **reads** other providers. Changes that affect routing, such as signing in
/// or out, reach the router through `refreshListenable`, which re-runs the
/// redirect without recreating it. Never make this provider `watch` anything.
///
/// The assembly is deliberately thin and should not grow with the app:
///
/// * **Routes** come from feature modules via [AppNavigationConfig] and
///   `AppModules`.
/// * **Access rules** come from the guard each route spec declares.
/// * **The decision** comes from the pure [RedirectPolicy].
///
/// ## Redirects and errors
///
/// * The redirect is synchronous on purpose. It runs on every navigation,
///   including the first frame, and anything async shows up as a flicker.
/// * `redirectLimit` is kept low. If it is ever hit, two rules contradict each
///   other, and a low limit turns a silent infinite loop into a loud assertion.
/// * A URL that matches no route is sent to the not-found page, with the typed
///   URL preserved so the page can display it.
///
/// ## Observers
///
/// Every navigator gets its **own** [AppRouteObserver], created through
/// `newObserver`. A `NavigatorObserver` cannot be shared between navigators:
/// `observer.navigator == null` is asserted on the first build.
///
/// ## Example
///
/// ```dart
/// class App extends ConsumerWidget {
///   const App({super.key});
///
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     return MaterialApp.router(routerConfig: ref.watch(routerProvider));
///   }
/// }
/// ```
///
/// See also:
///
/// * [RedirectPolicy], which decides every redirect.
/// * [RouterRefreshNotifier], which re-runs the redirect when auth changes.
/// * [NavigationService], which this router is attached to for navigation
///   without a `BuildContext`.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final navigation = ref.read(appNavigationProvider);
  final registry = ref.read(routeRegistryProvider);
  final talker = ref.read(talkerProvider);

  final refresh = RouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  const policy = RedirectPolicy();

  // One observer per navigator. Sharing an instance throws on the first build.
  AppRouteObserver newObserver(String label) => AppRouteObserver(talker, registry: registry, label: label);

  // Runs on every navigation. Reads auth rather than watching it: the provider
  // is keepAlive and must not rebuild, so `refresh` decides when this re-runs.
  String? onRedirect(BuildContext context, GoRouterState state) => policy(
    GuardContext(
      auth: ref.read(authControllerProvider),
      uri: state.uri,
      matchedLocation: state.matchedLocation,
      route: registry.resolve(state),
      homeFor: navigation.homeFor,
    ),
  );

  // Preserves the URL the user typed so the 404 page can show it.
  void onException(BuildContext context, GoRouterState state, GoRouter router) {
    talker.warning('[route] unmatched ${state.uri}');
    router.go(SystemRoutes.notFound.withQuery({RouteQuery.attempted: state.uri.toString()}));
  }

  final goRouter = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: SystemRoutes.login.path,
    debugLogDiagnostics: kDebugMode,
    restorationScopeId: 'cash_counter_pos_routes',
    refreshListenable: refresh,
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

  // Lets code with no BuildContext (Dio interceptors, notification handlers,
  // the deep-link handler) navigate through the router.
  NavigationService.instance.attach(goRouter, registry);
  ref.onDispose(() {
    NavigationService.instance.detach();
    goRouter.dispose();
  });

  return goRouter;
}
