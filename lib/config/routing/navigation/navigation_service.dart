import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../route_registry.dart';
import '../route_spec.dart';
import '../system_modules/system_routes.dart';

/// Navigation from outside the widget tree.
///
/// Needed by things that have no BuildContext: a Dio interceptor forcing
/// sign-out on a 401, a push-notification tap handler, a background sync
/// failure, a bluetooth printer disconnect. Everything with a context should
/// use the [AppNavigation] extension instead.
class NavigationService {
  NavigationService._();

  static final NavigationService instance = NavigationService._();

  GoRouter? _router;
  RouteRegistry? _registry;

  /// Called once from the router provider.
  void attach(GoRouter router, RouteRegistry registry) {
    _router = router;
    _registry = registry;
  }

  void detach() {
    _router = null;
    _registry = null;
  }

  bool get isReady => _router != null;

  GoRouter get _requireRouter {
    final router = _router;
    assert(router != null, 'NavigationService used before attach()');
    return router!;
  }

  // ==========================================================================
  // CORE
  // ==========================================================================

  void goTo(
    RouteSpec route, {
    Map<String, String> params = const {},
    Map<String, String?> query = const {},
    Object? extra,
  }) => _requireRouter.go(route.withParamsAndQuery(params, query), extra: extra);

  Future<T?> pushTo<T extends Object?>(
    RouteSpec route, {
    Map<String, String> params = const {},
    Map<String, String?> query = const {},
    Object? extra,
  }) => _requireRouter.push<T>(route.withParamsAndQuery(params, query), extra: extra);

  void replaceWith(
    RouteSpec route, {
    Map<String, String> params = const {},
    Map<String, String?> query = const {},
    Object? extra,
  }) => _requireRouter.pushReplacement(route.withParamsAndQuery(params, query), extra: extra);

  /// Raw location, for deep links that were already validated.
  void goToLocation(String location, {Object? extra}) => _requireRouter.go(location, extra: extra);

  void pop<T extends Object?>([T? result]) {
    if (_requireRouter.canPop()) _requireRouter.pop(result);
  }

  bool canPop() => _router?.canPop() ?? false;

  // ==========================================================================
  // STATE
  // ==========================================================================

  String get currentLocation => _requireRouter.routerDelegate.currentConfiguration.uri.toString();

  RouteSpec? get currentRoute => _registry?.byLocation(currentLocation);

  // ==========================================================================
  // CONVENIENCE
  // ==========================================================================

  /// Resets to a single entry rather than popping in a loop. Popping repeatedly
  /// races the framework and can leave the navigator mid-transition; `go`
  /// replaces the whole stack in one pass.
  void resetTo(RouteSpec route, {Map<String, String> params = const {}}) => _requireRouter.go(route.withParams(params));

  /// For the 401 path in your Dio interceptor. Clear the session first, then
  /// call this only if the redirect policy has not already moved the user.
  void forceSignOut() => resetTo(SystemRoutes.login);

  /// Confirm before navigating away from unsaved work.
  Future<bool> goWithConfirmation(
    BuildContext context,
    RouteSpec route, {
    Map<String, String> params = const {},
    String title = 'Leave this page?',
    String message = 'Unsaved changes will be lost.',
    String confirmLabel = 'Leave',
    String cancelLabel = 'Stay',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(confirmLabel)),
        ],
      ),
    );

    if (confirmed ?? false) {
      goTo(route, params: params);
      return true;
    }
    return false;
  }

  @visibleForTesting
  void debugAttach(GoRouter router, RouteRegistry registry) {
    _router = router;
    _registry = registry;
  }
}
