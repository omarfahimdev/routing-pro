import '../../../features/auth/domain/auth_state.dart';
import '../guards/guard_context.dart';
import '../guards/route_guard.dart';
import '../system_modules/system_routes.dart';

/// ============================================================================
/// NAVIGATION ACCESS IS DECIDED IN HERE.
///
/// Pure by design: no BuildContext, no Ref, no async, no side effects. It
/// handles the three *global* states that no per-route guard can see
/// (bootstrapping, the transient splash, a locked terminal) and delegates
/// everything else to the guard chain the route declares.
///
/// The rule that keeps this readable: global lifecycle lives here, per-route
/// access lives in the guard on the route's spec. Nothing is checked in both.
/// ============================================================================
class RedirectPolicy {
  const RedirectPolicy();

  String? call(GuardContext context) {
    final location = context.matchedLocation; // e.g. '/products/42' or '/splash'

    // STEP 1 - still waking up from disk. Park everything on the splash and
    // remember the destination in ?from= so a typed URL survives bootstrapping.
    if (context.auth.isBootstrapping) {
      return location == SystemRoutes.splash.path ? null : context.gate(SystemRoutes.splash);
    }

    // STEP 2 - bootstrapping is over; nobody stays on the splash.
    if (location == SystemRoutes.splash.path) {
      return switch (context.auth) {
        Authenticated(:final session) => context.returnTo ?? context.homeFor(session),
        SessionLocked() => SystemRoutes.lock.path,
        _ => SystemRoutes.login.path,
      };
    }

    // STEP 3 - PIN-locked register.
    // A: locked but trying to see another page -> /lock?from=...
    if (context.auth.isLocked && location != SystemRoutes.lock.path) {
      return context.gate(SystemRoutes.lock);
    }
    // B: unlocked but still sitting on /lock -> release to where they were.
    if (context.auth.isAuthenticated && location == SystemRoutes.lock.path) {
      return context.returnTo ?? context.homeFor(context.session!);
    }

    // STEP 4 - unknown link. Return null so GoRouter's onException shows the 404.
    final route = context.route;
    if (route == null) return null;

    // STEP 5 - terminal error pages are never guarded, or a guard redirecting
    // to /forbidden would try to guard /forbidden and loop.
    if (SystemRoutes.errorPages.contains(route)) return null;

    // STEP 6 - the route's own guard chain (its ancestors' guards included).
    return switch (route.accessGuard.evaluate(context)) {
      GuardAllow() => null,
      // Redirecting to the page we are already on would loop.
      GuardRedirect(location: final target) => target == context.uri.toString() ? null : target,
    };
  }
}
