import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../features/customers/presentation/routes/customers_routes.dart';
import '../../../features/reports/presentation/routes/reports_routes.dart';
import '../../../features/settings/presentation/routes/settings_routes.dart';
import '../guards/guards.dart';
import '../route_module.dart';
import '../route_spec.dart';
import '../screens/more_screen.dart';
import '../screens/route_inspector_screen.dart';

/// ============================================================================
/// THE "MORE" TAB: ONE NAVIGATOR HOSTING SEVERAL INDEPENDENT FEATURES.
///
/// Customers, reports and settings each own their routes. This module only
/// composes them under one tab so they share a back stack while URLs stay clean
/// (`/settings`, not `/more/settings`). It lives in `config` because the More
/// screen is navigation chrome - it reads the app's destination list.
/// ============================================================================
final class MoreModule implements RouteModule {
  const MoreModule();

  static const root = RouteSpec.root('/more', name: 'more', title: 'More', guard: Guards.auth);

  /// Dev tool: the whole route table with each guard's verdict for the session
  /// on screen. A child of [root], so it inherits `Guards.auth` for free.
  static const inspector = RouteSpec.child(root, 'routes', name: 'routeInspector', title: 'Route inspector');

  /// Independent features sharing this tab's navigator. Each owns its specs and
  /// its GoRoutes; this module only composes them, which is why their URLs stay
  /// top-level (`/settings`, not `/more/settings`).
  static const _features = <RouteModule>[CustomersRoutes(), ReportsRoutes(), SettingsRoutes()];

  @override
  List<RouteSpec> get specs => [root, inspector, for (final feature in _features) ...feature.specs];

  @override
  List<RouteBase> routes(GlobalKey<NavigatorState> rootNavigatorKey) => [
    root.route(
      builder: (context, state) => const MoreScreen(),
      routes: [inspector.route(builder: (context, state) => const RouteInspectorScreen())],
    ),
    for (final feature in _features) ...feature.routes(rootNavigatorKey),
  ];
}
