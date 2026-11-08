import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/session.dart';
import 'route_module.dart';
import 'route_spec.dart';
import 'system_modules/system_routes.dart';

/// ============================================================================
/// NAVIGATION CHROME - SEPARATE FROM ROUTING.
///
/// Icons, labels and "who sees this tab" are presentation. They used to live on
/// the route enum, which forced the routing layer to depend on Material icons
/// and made every nav tweak a change to the routing file.
/// ============================================================================
@immutable
final class NavDestination {
  const NavDestination({
    required this.spec,
    required this.label,
    required this.icon,
    IconData? activeIcon,
    this.permissions = const <String>{},
  }) : activeIcon = activeIcon ?? icon;

  final RouteSpec spec;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Decides whether the item is shown (and can be a landing page). Separate
  /// from the route's guard on purpose: the terminal tab stays visible to a
  /// cashier with no open shift and the shift gate stops them at the door.
  final Set<String> permissions;

  bool isVisibleFor(Session session) => session.canAll(permissions);
}

/// One tab = one destination + the module that fills its navigator.
/// Tab order and branch order are the same list, so they cannot drift.
final class ShellBranch {
  ShellBranch({required this.destination, required this.module})
    : navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'branch.${destination.spec.name}');

  final NavDestination destination;
  final RouteModule module;
  final GlobalKey<NavigatorState> navigatorKey;
}

/// The tab bar, drawer and landing-page rules, built once.
final class AppNavigation {
  AppNavigation({required List<ShellBranch> branches, required List<NavDestination> drawer})
    : branches = List.unmodifiable(branches),
      drawer = List.unmodifiable(drawer) {
    _validate();
  }

  final List<ShellBranch> branches;

  /// The drawer, the rail's overflow and the More screen.
  final List<NavDestination> drawer;

  List<NavDestination> get tabs => [for (final branch in branches) branch.destination];

  List<NavDestination> visibleTabs(Session session) =>
      List.unmodifiable(tabs.where((destination) => destination.isVisibleFor(session)));

  List<NavDestination> visibleDrawer(Session session) =>
      List.unmodifiable(drawer.where((destination) => destination.isVisibleFor(session)));

  /// Branch index of a tab. They differ from the visible index whenever
  /// permissions hide a tab. -1 when [destination] is not a tab.
  int branchOf(NavDestination destination) => tabs.indexOf(destination);

  NavDestination? tabForBranch(int branch) => branch >= 0 && branch < branches.length ? tabs[branch] : null;

  /// First tab this session may see. Hard-coding `/dashboard` is what sends
  /// cashiers straight into a 403.
  String homeFor(Session session) {
    for (final destination in tabs) {
      if (destination.isVisibleFor(session)) return destination.spec.path;
    }
    return SystemRoutes.forbidden.path;
  }

  /// Builds the stateful shell straight from [branches], so there is no
  /// "reorder these two lists together" contract left to break.
  /// [observerFactory] is called ONCE PER BRANCH and must return fresh
  /// observers each time: a NavigatorObserver can serve exactly one Navigator,
  /// so reusing one instance trips `assert(observer.navigator == null)` on the
  /// first build.
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
      if (tabs.toSet().length != tabs.length) throw StateError('A destination is used by two tabs');
      for (final destination in {...tabs, ...drawer}) {
        if (destination.spec.path.contains(':')) {
          throw StateError('${destination.spec.name} is a nav destination but its path needs params');
        }
      }
      return true;
    }());
  }
}
