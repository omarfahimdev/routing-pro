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
import 'system_modules/auth_module.dart';
import 'system_modules/more_module.dart';
import 'system_modules/system_module.dart';
import 'route_module.dart';

/// ============================================================================
/// THE COMPOSITION ROOT - THE ONLY FILE THAT KNOWS EVERY FEATURE.
///
/// Adding a feature: write its module, add one line here (a tab in
/// [buildAppNavigation] or a top-level module in [AppModules]). This file grows
/// by one line per feature; no route is ever declared in it.
/// ============================================================================
abstract final class AppModules {
  const AppModules._();

  /// Routes outside the tab shell: system pages, auth, full-screen flows.
  static const topLevel = <RouteModule>[SystemModule(), AuthModule(), CheckoutRoutes()];
}

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
