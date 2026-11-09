/// The app's navigation chrome: tabs, drawer and landing-page rules.
///
/// Routing decides **where** a path leads and **who may open it**. This library
/// decides what the user **sees** in the tab bar, rail and drawer. Icons,
/// labels and "who sees this tab" are presentation. They used to live on the
/// route enum, which forced the routing layer to depend on Material icons and
/// made every navigation tweak a change to the routing file.
///
/// Three types work together:
///
/// * [NavDestination] is one entry in the chrome: a route spec plus its label,
///   icons and visibility rule.
/// * [ShellBranch] pairs a tab's destination with the route module that fills
///   its navigator.
/// * [AppNavigation] holds the ordered branches and the drawer, answers
///   visibility questions for a session, and builds the stateful shell.
///
/// ## Example
///
/// ```dart
/// final navigation = AppNavigation(
///   branches: [
///     ShellBranch(destination: dashboard, module: const DashboardRoutes()),
///     ShellBranch(destination: orders, module: const OrdersRoutes()),
///   ],
///   drawer: const [dashboard, orders, settings],
/// );
///
/// final tabs = navigation.visibleTabs(session);
/// final landing = navigation.homeFor(session);
/// ```
///
/// See also:
///
/// * `buildAppNavigation`, the composition root that declares the real tabs.
/// * `RouteModule`, which supplies the routes for each branch.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/session.dart';
import 'route_module.dart';
import 'route_spec.dart';
import 'system_modules/system_routes.dart';

/// One entry in the navigation chrome: a route plus how it is presented.
///
/// A destination appears in the tab bar, the rail or the drawer. It is
/// immutable and `const`, so the same instance can be shared by a tab list and
/// the drawer list.
///
/// ```dart
/// const orders = NavDestination(
///   spec: OrdersRoutes.list,
///   label: 'Orders',
///   icon: Icons.receipt_long_outlined,
///   activeIcon: Icons.receipt_long,
///   permissions: {Permissions.viewOrders},
/// );
/// ```
@immutable
final class NavDestination {
  /// Creates a destination for [spec].
  ///
  /// [activeIcon] defaults to [icon] when the selected state uses the same
  /// glyph. [permissions] defaults to empty, which makes the destination
  /// visible to every signed-in user.
  const NavDestination({
    required this.spec,
    required this.label,
    required this.icon,
    IconData? activeIcon,
    this.permissions = const <String>{},
  }) : activeIcon = activeIcon ?? icon;

  /// The route this destination opens.
  ///
  /// Its path must not contain parameters, since a tab cannot supply them.
  final RouteSpec spec;

  /// The text shown beside or under the icon.
  final String label;

  /// The icon shown when the destination is not selected.
  final IconData icon;

  /// The icon shown when the destination is selected.
  final IconData activeIcon;

  /// The `resource:action` keys a session must hold for this destination to be
  /// shown, and to be considered as a landing page.
  ///
  /// Deliberately separate from the guard on [spec]. The terminal tab stays
  /// visible to a cashier who has not opened a shift, and the shift gate stops
  /// them at the door instead of the tab disappearing. Keep the two in step, or
  /// a tab can appear that leads to a 403.
  final Set<String> permissions;

  /// Whether [session] holds every permission in [permissions].
  ///
  /// Always `true` when [permissions] is empty.
  bool isVisibleFor(Session session) => session.canAll(permissions);
}

/// One tab: a destination and the module that fills its navigator.
///
/// Each branch owns a [navigatorKey], so every tab keeps its own back stack.
/// Because the key is a `GlobalKey`, a [ShellBranch] cannot be `const`.
final class ShellBranch {
  /// Creates a branch whose navigator key is labelled after the destination.
  ShellBranch({required this.destination, required this.module})
    : navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'branch.${destination.spec.name}');

  /// What the tab bar shows for this branch.
  final NavDestination destination;

  /// The routes that live inside this tab's navigator.
  final RouteModule module;

  /// The key of this tab's navigator.
  final GlobalKey<NavigatorState> navigatorKey;
}

/// The tab bar, drawer and landing-page rules, built once.
///
/// Tab order **is** branch order: both come from the single [branches] list, so
/// there is no second list to reorder in step.
///
/// Create one instance and keep it for the app's lifetime. Each [ShellBranch]
/// holds a `GlobalKey`, so building a second instance gives the same tabs new
/// navigator keys and discards every tab's back stack.
final class AppNavigation {
  /// Creates the navigation from [branches] and [drawer].
  ///
  /// Both lists are copied and become unmodifiable. In debug builds the
  /// constructor asserts that no destination is used by two tabs and that no
  /// destination path needs parameters.
  AppNavigation({required List<ShellBranch> branches, required List<NavDestination> drawer})
    : branches = List.unmodifiable(branches),
      drawer = List.unmodifiable(drawer),
      tabs = List.unmodifiable([for (final branch in branches) branch.destination]) {
    _validate();
  }

  /// The tabs, in display order. The index of a branch is its shell branch
  /// index.
  final List<ShellBranch> branches;

  /// The drawer, the rail's overflow and the More screen, in display order.
  final List<NavDestination> drawer;

  /// The destination of every branch, in the same order as [branches].
  final List<NavDestination> tabs;

  /// The tabs [session] may see, in display order.
  List<NavDestination> visibleTabs(Session session) =>
      List.unmodifiable(tabs.where((destination) => destination.isVisibleFor(session)));

  /// The drawer entries [session] may see, in display order.
  List<NavDestination> visibleDrawer(Session session) =>
      List.unmodifiable(drawer.where((destination) => destination.isVisibleFor(session)));

  /// The shell branch index of [destination], or `-1` if it is not a tab.
  ///
  /// This differs from the visible index whenever permissions hide a tab. For a
  /// cashier without the dashboard, visible position 0 is the terminal, which is
  /// branch 1.
  ///
  /// Matching is by identity, so pass the same instance that was used to build
  /// the branch.
  int branchOf(NavDestination destination) => tabs.indexOf(destination);

  /// The destination that owns [branch], or `null` when [branch] is out of
  /// range.
  NavDestination? tabForBranch(int branch) => branch >= 0 && branch < tabs.length ? tabs[branch] : null;

  /// The location a signed-in [session] lands on: the first tab it may see.
  ///
  /// Hard-coding `/dashboard` is what sends cashiers straight into a 403. Falls
  /// back to the forbidden page when no tab is visible.
  ///
  /// Visibility is decided by [NavDestination.permissions] only. If a tab's
  /// route guard is stricter, the redirect policy still applies it on arrival.
  String homeFor(Session session) {
    for (final destination in tabs) {
      if (destination.isVisibleFor(session)) return destination.spec.path;
    }
    return SystemRoutes.forbidden.path;
  }

  /// Builds the stateful shell route straight from [branches].
  ///
  /// Because the shell is generated from the same list as the tabs, there is no
  /// "reorder these two lists together" contract left to break.
  ///
  /// [rootNavigatorKey] is passed to each module so its full-screen routes can
  /// render above the shell. [shellBuilder] creates the chrome around the
  /// active branch.
  ///
  /// [observerFactory] is called **once per branch** and must return fresh
  /// observers each time. A `NavigatorObserver` can serve exactly one
  /// navigator, so reusing an instance trips
  /// `assert(observer.navigator == null)` on the first build.
  ///
  /// ```dart
  /// navigation.buildShell(
  ///   rootNavigatorKey: rootNavigatorKey,
  ///   observerFactory: (branch) => [AppRouteObserver(talker, registry: r)],
  ///   shellBuilder: (context, state, shell) =>
  ///       MainShell(navigationShell: shell),
  /// );
  /// ```
  RouteBase buildShell({
    required GlobalKey<NavigatorState> rootNavigatorKey,
    required Widget Function(BuildContext context, GoRouterState state, StatefulNavigationShell shell) shellBuilder,
    List<NavigatorObserver> Function(ShellBranch branch)? observerFactory,
  }) => StatefulShellRoute.indexedStack(
    pageBuilder: (context, state, shell) =>
        NoTransitionPage<void>(key: state.pageKey, child: shellBuilder(context, state, shell)),
    branches: [
      for (final branch in branches)
        StatefulShellBranch(
          navigatorKey: branch.navigatorKey,
          observers: observerFactory == null ? const <NavigatorObserver>[] : observerFactory(branch),
          initialLocation: branch.destination.spec.path,
          routes: branch.module.routes(rootNavigatorKey),
        ),
    ],
  );

  void _validate() {
    assert(() {
      if (tabs.toSet().length != tabs.length) {
        throw StateError('A destination is used by two tabs');
      }
      for (final destination in {...tabs, ...drawer}) {
        if (destination.spec.path.contains(':')) {
          throw StateError(
            '${destination.spec.name} is a nav destination but its path '
            'needs params',
          );
        }
      }
      return true;
    }());
  }
}
