import '../../../features/auth/domain/auth_state.dart';
import '../guards/guard_context.dart';
import '../guards/route_guard.dart';
import '../system_modules/system_routes.dart';

/// Decides, for every navigation, whether to let it through or redirect.
///
/// The policy is pure: no `BuildContext`, no `Ref`, no async work and no side
/// effects. Everything it needs arrives on the [GuardContext], which makes it
/// unit-testable without a widget tree. go_router runs it on every navigation,
/// including the first frame.
///
/// ## Division of responsibility
///
/// * **Global lifecycle lives here.** Bootstrapping, the splash and the lock
///   screen are states no per-route guard can see.
/// * **Per-route access lives in the route's guard.** The policy delegates to
///   `RouteSpec.accessGuard`, which already includes the ancestors' guards.
///
/// Nothing is checked in both places.
///
/// ## Decision order
///
/// The first matching step wins.
///
/// | Step | Condition                                | Result                         |
/// | ---- | ---------------------------------------- | ------------------------------ |
/// | 1    | Session is still being restored          | Park on splash, keep `?from=`  |
/// | 2    | On splash, restore finished              | Home, lock or sign-in          |
/// | 3A   | Locked, on any page but `/lock`          | `/lock`, keep `?from=`         |
/// | 3B   | Unlocked, still on `/lock`               | Back to `?from=` or home       |
/// | 4    | URL matches no route                     | No redirect (`onException`)    |
/// | 5    | Terminal error page                      | No redirect, never guarded     |
/// | 6    | Anything else                            | The route's guard chain        |
///
/// A redirect that points at the current location is suppressed (returned as
/// `null`) so a guard cannot loop on itself. Longer cycles are caught by
/// `GoRouter.redirectLimit`.
///
/// ## Example
///
/// ```dart
/// const policy = RedirectPolicy();
///
/// final context = GuardContext.parse(
///   '/reports',
///   const AuthState.unauthenticated(),
///   registry: registry,
/// );
///
/// policy(context); // '/login?from=%2Freports'
/// ```
class RedirectPolicy {
  /// Creates the redirect policy.
  const RedirectPolicy();

  /// Returns the location to redirect to, or `null` to allow the navigation.
  ///
  /// Returning `null` for an unmatched URL is intentional: go_router's
  /// `onException` handler then shows the not-found page.
  String? call(GuardContext context) {
    final location = context.matchedLocation; // e.g. '/products/42'

    // Step 1: still restoring the session from disk. Park every navigation on
    // the splash and keep the destination in ?from= so a typed URL survives
    // bootstrapping.
    if (context.auth.isBootstrapping) {
      return location == SystemRoutes.splash.path ? null : context.gate(SystemRoutes.splash);
    }

    // Step 2: bootstrapping is over, so nobody stays on the splash.
    if (location == SystemRoutes.splash.path) {
      return switch (context.auth) {
        Authenticated(:final session) => context.returnTo ?? context.homeFor(session),
        SessionLocked() => SystemRoutes.lock.path,
        _ => SystemRoutes.login.path,
      };
    }

    // Step 3: PIN-locked register.
    // A: locked, but trying to see another page.
    if (context.auth.isLocked && location != SystemRoutes.lock.path) {
      return context.gate(SystemRoutes.lock);
    }
    // B: unlocked, but still sitting on /lock. Release to where they were.
    if (context.auth.isAuthenticated && location == SystemRoutes.lock.path) {
      return context.returnTo ?? context.homeFor(context.session!);
    }

    // Step 4: unknown link. Return null so onException shows the 404.
    final route = context.route;
    if (route == null) return null;

    // Step 5: terminal error pages are never guarded. A guard that redirects
    // to /forbidden would otherwise try to guard /forbidden and loop.
    if (SystemRoutes.errorPages.contains(route)) return null;

    // Step 6: the route's own guard chain, ancestors included.
    return switch (route.accessGuard.evaluate(context)) {
      GuardAllow() => null,
      // Redirecting to the page we are already on would loop.
      GuardRedirect(location: final target) => target == context.uri.toString() ? null : target,
    };
  }
}
