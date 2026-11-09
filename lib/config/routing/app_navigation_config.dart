import 'package:flutter/material.dart';

import '../../core/constants/permissions.dart';
import '../../features/catalog/presentation/routes/catalog_routes.dart';
import '../../features/checkout/presentation/routes/checkout_routes.dart';
import '../../features/customers/presentation/routes/customers_routes.dart';
import '../../features/dashboard/presentation/routes/dashboard_routes.dart';
import '../../features/orders/presentation/routes/orders_routes.dart';
import '../../features/reports/presentation/routes/reports_routes.dart';
import '../../features/settings/presentation/routes/settings_routes.dart';
import '../../features/terminal/presentation/routes/terminal_routes.dart';
import 'app_navigation.dart';
import 'route_module.dart';
import 'system_modules/auth_module.dart';
import 'system_modules/more_module.dart';
import 'system_modules/system_module.dart';

/// The route modules that live outside the tab shell.
///
/// This file is the composition root: the only place that knows every feature.
/// Adding a feature means writing its module and adding **one line** here,
/// either a tab in [buildAppNavigation] or a top-level module in [topLevel].
/// No route is ever declared in this file.
///
/// ```dart
// / // A new full-screen feature outside the tab shell:
/// static const topLevel = <RouteModule>[
///   SystemModule(),
///   AuthModule(),
///   CheckoutRoutes(),
///   ReceiptsRoutes(), // <- one line
/// ];
/// ```
///
/// See also:
///
/// * [buildAppNavigation], which declares the tabs and the drawer.
abstract final class AppModules {
  const AppModules._();

  /// Modules mounted directly on the root navigator: system pages, auth and
  /// full-screen flows such as checkout.
  ///
  /// The router spreads each module's `routes` into its top-level route list.
  static const topLevel = <RouteModule>[SystemModule(), AuthModule(), CheckoutRoutes()];
}

/// Builds the app's navigation: the tab branches and the drawer.
///
/// ## Ordering contract
///
/// The order of `branches` is the tab order **and** the shell branch order, so
/// branch 0 is the first tab, branch 1 the second, and so on. Reordering a tab
/// means moving one line in `branches`; nothing else needs to change.
///
/// ## Visibility
///
/// A destination's `permissions` decide whether its tab or drawer entry is
/// **shown**. They are separate from the guard on the route spec, which decides
/// whether the route may be **opened**. For example, the terminal tab is shown
/// to anyone holding `operateTerminal`, and the shift gate then stops a cashier
/// who has not opened a register. A destination with no permissions is visible
/// to every signed-in user.
///
/// Keep each destination's `permissions` in step with the guard on its spec,
/// or a tab can appear that leads to a 403.
///
/// ## Tabs and drawer
///
/// * **Tabs** (`branches`): dashboard, terminal, orders, products, more.
/// * **Drawer**: the tabs above plus customers, reports and settings. Those
///   three are not tabs; they are routes owned by [MoreModule], which mounts
///   them in the **More** branch so they share one tab and back stack.
///
/// ## Example
///
/// ```dart
/// final navigation = buildAppNavigation();
/// ```
AppNavigation buildAppNavigation() {
  const dashboard = NavDestination(
    spec: DashboardRoutes.root,
    label: 'Dashboard',
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
  );
  const terminal = NavDestination(
    spec: TerminalRoutes.root,
    label: 'Terminal',
    icon: Icons.point_of_sale_outlined,
    activeIcon: Icons.point_of_sale,
    permissions: {Permissions.operateTerminal},
  );
  const orders = NavDestination(
    spec: OrdersRoutes.list,
    label: 'Orders',
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long,
    permissions: {Permissions.viewOrders},
  );
  const products = NavDestination(
    spec: CatalogRoutes.list,
    label: 'Products',
    icon: Icons.inventory_2_outlined,
    activeIcon: Icons.inventory_2,
    permissions: {Permissions.viewProducts},
  );
  const more = NavDestination(
    spec: MoreModule.root,
    label: 'More',
    icon: Icons.more_horiz_outlined,
    activeIcon: Icons.more_horiz,
  );
  const customers = NavDestination(
    spec: CustomersRoutes.list,
    label: 'Customers',
    icon: Icons.people_outline,
    activeIcon: Icons.people,
    permissions: {Permissions.viewCustomers},
  );
  const reports = NavDestination(
    spec: ReportsRoutes.root,
    label: 'Reports',
    icon: Icons.bar_chart_outlined,
    activeIcon: Icons.bar_chart,
    permissions: {Permissions.viewReports},
  );
  const settings = NavDestination(
    spec: SettingsRoutes.list,
    label: 'Settings',
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
    permissions: {Permissions.viewSettings},
  );

  return AppNavigation(
    // List order IS tab order IS branch order.
    branches: [
      ShellBranch(destination: dashboard, module: const DashboardRoutes()),
      ShellBranch(destination: terminal, module: const TerminalRoutes()),
      ShellBranch(destination: orders, module: const OrdersRoutes()),
      ShellBranch(destination: products, module: const CatalogRoutes()),
      ShellBranch(destination: more, module: const MoreModule()),
    ],
    drawer: const [dashboard, terminal, orders, products, customers, reports, settings],
  );
}
