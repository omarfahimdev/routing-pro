import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../guards/guard_context.dart';
import '../route_module.dart';
import '../route_params.dart';
import '../route_spec.dart';
import '../screens/system_screens.dart';
import 'system_routes.dart';

/// ============================================================================
/// WIRES THE SYSTEM SPECS (core) TO THEIR SCREENS (config).
///
/// `?from=` is attacker-controllable on web, so it is sanitised here once
/// instead of trusting each screen to remember.
///
/// Owns: splash, lock, open-shift, 403, 404, error. Sign-in and password
/// recovery belong to [AuthModule]. The specs themselves live in
/// `SystemRoutes` because guards and the redirect policy depend on them.
/// ============================================================================
final class SystemModule implements RouteModule {
  const SystemModule();

  @override
  List<RouteSpec> get specs => const [
    SystemRoutes.splash,
    SystemRoutes.lock,
    SystemRoutes.openShift,
    SystemRoutes.forbidden,
    SystemRoutes.notFound,
    SystemRoutes.error,
  ];

  @override
  List<RouteBase> routes(GlobalKey<NavigatorState> rootNavigatorKey) => [
    // Bare web root. The redirect policy decides where the splash sends the user.
    GoRoute(path: '/', redirect: (context, state) => SystemRoutes.splash.path),
    SystemRoutes.splash.route(builder: (context, state) => const SplashScreen()),
    SystemRoutes.lock.route(
      builder: (context, state) => LockScreen(returnTo: GuardContext.sanitizeReturnTo(state.query(RouteQuery.from))),
    ),
    SystemRoutes.openShift.route(
      builder: (context, state) =>
          OpenShiftScreen(returnTo: GuardContext.sanitizeReturnTo(state.query(RouteQuery.from))),
    ),
    SystemRoutes.forbidden.route(
      builder: (context, state) => ForbiddenScreen(attempted: state.query(RouteQuery.attempted)),
    ),
    SystemRoutes.notFound.route(
      builder: (context, state) => NotFoundScreen(attempted: state.query(RouteQuery.attempted)),
    ),
    SystemRoutes.error.route(builder: (context, state) => AppErrorScreen(message: state.query('message'))),
  ];
}
