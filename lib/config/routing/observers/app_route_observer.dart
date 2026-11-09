/// A navigator observer that records route breadcrumbs and screen views.
///
/// [AppRouteObserver] writes every navigation event into the same Talker
/// stream as the Dio and Riverpod logs, so a bug report reads as one story:
/// tapped, navigated, request, 500. It is also the single place that emits
/// screen-view analytics, keyed off the route spec's `analyticsId` rather than
/// a raw URL that may contain customer ids.
///
/// ## One instance per navigator
///
/// Create a **separate** observer for every navigator, and never share one.
/// A [NavigatorObserver] holds a back-reference to the navigator it serves, and
/// `NavigatorState.initState` asserts that `observer.navigator` is `null`.
/// Sharing one instance between the root navigator and a shell branch throws on
/// the first build. This is why the shell takes a factory rather than a list of
/// observers (see `AppNavigation.buildShell`).
///
/// A navigator also reports only its own stack, so attach an observer to the
/// root navigator **and** to each shell branch. Use [label] to tell them apart
/// in the log.
///
/// ## Example
///
/// ```dart
/// // Root navigator.
/// observers: [AppRouteObserver(talker, registry: registry)],
///
/// // One per shell branch, labelled with the branch name.
/// StatefulShellBranch(
///   observers: [
///     AppRouteObserver(talker, registry: registry, label: 'orders'),
///   ],
///   routes: orderRoutes,
/// ),
/// ```
///
/// The log then shows which stack moved:
///
/// ```text
/// [route:root] push /login (from -)
/// [route:orders] push /orders/42 (from /orders)
/// ```
///
/// See also:
///
/// * [NavigatorObserver], the Flutter class this extends.
/// * [RouteRegistry], used to resolve a route name to its spec.
library;

import 'package:flutter/widgets.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../route_registry.dart';

/// Logs navigation events for one navigator and reports screen views.
///
/// Routes without a `settings.name`, such as dialogs and bottom sheets opened
/// without a name, are ignored.
class AppRouteObserver extends NavigatorObserver {
  final Talker _talker;

  /// Resolves a route name or location to its [RouteSpec].
  final RouteRegistry registry;

  /// Names the navigator this instance watches, `'root'` or a branch name.
  ///
  /// Appears in every log line as `[route:<label>]`.
  final String label;

  /// Called with a route's `analyticsId` when a screen is entered.
  ///
  /// Not called for pops or removals, and not called for routes the registry
  /// cannot resolve.
  final void Function(String screenName)? onScreenView;

  /// Creates an observer for a single navigator.
  ///
  /// [registry] resolves route names to specs for analytics. [label] names the
  /// navigator in log lines. [onScreenView] is called with the route's
  /// `analyticsId` whenever a screen becomes visible by being pushed or
  /// replaced; leave it `null` to log without sending analytics.
  AppRouteObserver(this._talker, {required this.registry, this.label = 'root', this.onScreenView});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _record('push', route, previousRoute, isEntry: true);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _record('pop', route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _record('replace', newRoute, oldRoute, isEntry: true);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _record('remove', route, previousRoute);
  }

  /// Logs one navigation event and, for entries, emits a screen view.
  ///
  /// [isEntry] is `true` for pushes and replacements, the two events that make
  /// a new screen visible.
  void _record(String action, Route<dynamic>? route, Route<dynamic>? previous, {bool isEntry = false}) {
    final name = route?.settings.name;
    if (name == null) return;

    final from = previous?.settings.name ?? '-';
    _talker.logCustom(TalkerLog('[route:$label] $action $name (from $from)'));

    final report = onScreenView;
    if (!isEntry || report == null) return;

    // A route name is either a go_router name or a location that may carry a
    // query string. Strip the query before the location lookup.
    final spec = registry.byName(name) ?? registry.byLocation(name.split('?').first);
    if (spec != null) report(spec.analyticsId);
  }
}
