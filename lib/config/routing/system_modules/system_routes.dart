import '../guards/guards.dart';
import '../route_params.dart';
import '../route_spec.dart';
import '../transitions/route_transitions.dart';

/// SPECS THE ROUTER INFRASTRUCTURE ITSELF DEPENDS ON.
///
/// Guards redirect to login/forbidden and the policy parks users on splash/
/// lock, so these live in core, not in a feature. This is data only - the
/// screens are attached in `config/routing/modules` (SystemModule/AuthModule),
/// which keeps core free of screen and feature imports.
abstract final class SystemRoutes {
  const SystemRoutes._();

  static const splash = RouteSpec.root('/splash', name: 'splash', transition: TransitionPreset.none);

  static const login = RouteSpec.root(
    '/login',
    name: 'login',
    title: 'Sign in',
    guard: Guards.guest,
    transition: TransitionPreset.none,
  );

  static const forgotPassword = RouteSpec.root(
    '/forgot-password',
    name: 'forgotPassword',
    title: 'Reset password',
    guard: Guards.guest,
  );

  static const resetPassword = RouteSpec.root(
    '/reset-password/:${RouteParams.token}',
    name: 'resetPassword',
    title: 'Choose a new password',
    guard: Guards.guest,
  );

  static const lock = RouteSpec.root(
    '/lock',
    name: 'lock',
    title: 'Locked',
    transition: TransitionPreset.none,
    fullscreen: true,
  );

  static const openShift = RouteSpec.root(
    '/shift/open',
    name: 'openShift',
    title: 'Open register',
    guard: Guards.auth,
    transition: TransitionPreset.slideFromBottom,
    fullscreen: true,
  );

  static const forbidden = RouteSpec.root('/forbidden', name: 'forbidden', title: 'No access');
  static const notFound = RouteSpec.root('/404', name: 'notFound', title: 'Page not found');
  static const error = RouteSpec.root('/error', name: 'error', title: 'Something went wrong');

  /// Screens that must never be recorded as a "return to" destination -
  /// that is how redirect loops start.
  static const gates = <RouteSpec>[
    splash,
    login,
    forgotPassword,
    resetPassword,
    lock,
    openShift,
    forbidden,
    notFound,
    error,
  ];

  /// Pages the redirect policy leaves alone so a guard cannot loop on them.
  static const errorPages = <RouteSpec>{forbidden, notFound, error};

  static bool isGate(String path) => gates.any((gate) => gate.matches(path));
}
