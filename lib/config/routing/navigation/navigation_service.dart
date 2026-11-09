import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../route_registry.dart';
import '../route_spec.dart';
import '../system_modules/system_routes.dart';
import 'navigation_extensions.dart';

/// Navigates the app from code that has no [BuildContext].
///
/// Some callers live outside the widget tree: a Dio interceptor forcing
/// sign-out on a 401, a push-notification tap handler, a background sync
/// failure, a Bluetooth printer disconnect. They reach the router through this
/// singleton. Code that does have a context should use the [AppNavigation]
/// extension instead, which resolves the router from the widget tree.
///
/// ## Lifecycle
///
/// The router provider calls [attach] once when it builds and [detach] when it
/// is disposed. Until [attach] runs, every navigating method throws a
/// [StateError]. Check [isReady] when a caller may fire before startup has
/// finished.
///
/// ## Example
///
/// ```dart
/// // In a Dio interceptor, on a 401:
/// onError: (error, handler) {
///   if (error.response?.statusCode == 401) {
///     ref.read(authControllerProvider.notifier).signOut();
///     NavigationService.instance.forceSignOut();
///   }
///   handler.next(error);
/// },
///
/// // In a notification tap handler:
/// NavigationService.instance.goTo(
///   AppRoute.orderDetail,
///   params: {RouteParams.orderId: payload.orderId},
/// );
/// ```
///
/// See also:
///
/// * [AppNavigation], the `BuildContext` equivalent of this API.
/// * [RouteSpec], which every method takes instead of a path string.
class NavigationService {
  NavigationService._();

  /// The shared instance.
  static final NavigationService instance = NavigationService._();

  GoRouter? _router;
  RouteRegistry? _registry;

  /// Connects the service to the live [router].
  ///
  /// Called once by the router provider. [registry] is kept so [currentRoute]
  /// can resolve the active location to its [RouteSpec].
  void attach(GoRouter router, RouteRegistry registry) {
    _router = router;
    _registry = registry;
  }

  /// Disconnects the service from the router.
  ///
  /// Called when the router provider is disposed, so the singleton never holds
  /// a disposed [GoRouter].
  void detach() {
    _router = null;
    _registry = null;
  }

  /// Whether [attach] has been called and the router is available.
  bool get isReady => _router != null;

  GoRouter get _requireRouter {
    final router = _router;
    if (router == null) {
      throw StateError('NavigationService used before attach().');
    }
    return router;
  }

  // ---------------------------------------------------------------------------
  // Core navigation
  // ---------------------------------------------------------------------------

  /// Replaces the navigation stack with [route].
  ///
  /// Fills [route]'s path placeholders from [params] and appends [query] as the
  /// query string. Entries in [query] that are `null` or empty are omitted.
  /// Use this for anything the browser back button should treat as a page
  /// change.
  ///
  /// ```dart
  /// NavigationService.instance.goTo(
  ///   AppRoute.orders,
  ///   query: {RouteQuery.status: 'refunded'},
  /// );
  /// ```
  void goTo(
    RouteSpec route, {
    Map<String, String> params = const {},
    Map<String, String?> query = const {},
    Object? extra,
  }) => _requireRouter.go(route.withParamsAndQuery(params, query), extra: extra);

  /// Pushes [route] on top of the current stack.
  ///
  /// Returns a future that completes with the value the pushed page passes to
  /// `pop`. Reserve this for stacked flows the user backs out of, such as
  /// checkout, refunds and pickers. Deep `push` chains create browser history
  /// entries that are hard to reason about.
  ///
  /// ```dart
  /// final refunded = await NavigationService.instance.pushTo<bool>(
  ///   AppRoute.orderRefund,
  ///   params: {RouteParams.orderId: orderId},
  /// );
  /// ```
  Future<T?> pushTo<T extends Object?>(
    RouteSpec route, {
    Map<String, String> params = const {},
    Map<String, String?> query = const {},
    Object? extra,
  }) => _requireRouter.push<T>(route.withParamsAndQuery(params, query), extra: extra);

  /// Replaces the top of the stack with [route].
  ///
  /// The page being replaced cannot be returned to with the back button.
  void replaceWith(
    RouteSpec route, {
    Map<String, String> params = const {},
    Map<String, String?> query = const {},
    Object? extra,
  }) => _requireRouter.pushReplacement(route.withParamsAndQuery(params, query), extra: extra);

  /// Navigates to a raw [location] string.
  ///
  /// Intended for links that have already been validated, such as the output
  /// of `DeepLinkHandler.resolve`. The redirect policy still runs, so
  /// authentication and permission guards apply.
  ///
  /// This method does **not** validate [location]. A value taken from a
  /// `?from=` query must go through `GuardContext.sanitizeReturnTo` first, or
  /// it becomes an open redirect.
  void goToLocation(String location, {Object? extra}) => _requireRouter.go(location, extra: extra);

  /// Pops the current route, if there is one to pop.
  ///
  /// Does nothing when the stack has a single entry, so it is safe to call from
  /// a deep-linked cold start. Use `AppNavigation.popOr` to fall back to a
  /// route instead.
  void pop<T extends Object?>([T? result]) {
    if (_requireRouter.canPop()) _requireRouter.pop(result);
  }

  /// Whether the router has a route to pop.
  ///
  /// Returns `false`, rather than throwing, before [attach] has run.
  bool canPop() => _router?.canPop() ?? false;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// The current location including its query string, for example
  /// `/orders/42?status=open`.
  ///
  /// Throws a [StateError] before [attach] has run.
  String get currentLocation => _requireRouter.routerDelegate.currentConfiguration.uri.toString();

  /// The [RouteSpec] for the current location, or `null` when it matches no
  /// route or the service is not attached.
  RouteSpec? get currentRoute {
    final uri = _requireRouter.routerDelegate.currentConfiguration.uri;
    return _registry?.byLocation(uri.path);
  }

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  /// Resets the stack to a single entry, [route].
  ///
  /// Uses `go` rather than popping in a loop. Repeated pops race the framework
  /// and can leave the navigator mid-transition, whereas `go` replaces the
  /// whole stack in one pass.
  void resetTo(RouteSpec route, {Map<String, String> params = const {}}) => _requireRouter.go(route.withParams(params));

  /// Sends the user to the sign-in page after a forced sign-out.
  ///
  /// For the 401 path of a Dio interceptor. **Clear the session first.** The
  /// sign-in route is guest-only, so if the session is still authenticated the
  /// guard redirects the user straight back to their landing page. When
  /// clearing the session already triggers the redirect policy, this call is
  /// redundant but harmless.
  ///
  /// ```dart
  /// ref.read(authControllerProvider.notifier).signOut();
  /// NavigationService.instance.forceSignOut();
  /// ```
  void forceSignOut() => resetTo(SystemRoutes.login);

  /// Asks for confirmation, then navigates to [route] if the user agrees.
  ///
  /// Shows an [AlertDialog] built from [title], [message], [confirmLabel] and
  /// [cancelLabel]. Returns `true` if the user confirmed and navigation
  /// happened, `false` if they stayed or dismissed the dialog.
  ///
  /// Use it before leaving a page with unsaved work.
  ///
  /// ```dart
  /// final left = await NavigationService.instance.goWithConfirmation(
  ///   context,
  ///   AppRoute.orders,
  /// );
  /// ```
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

  /// Attaches a router in tests, bypassing the router provider.
  ///
  /// Call [detach] in `tearDown` so state does not leak between tests, since
  /// this class is a singleton.
  @visibleForTesting
  void debugAttach(GoRouter router, RouteRegistry registry) {
    _router = router;
    _registry = registry;
  }
}
