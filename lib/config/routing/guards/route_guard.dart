/// The contract every route guard implements, and the result it returns.
///
/// A [RouteGuard] inspects a [GuardContext] and answers with a [GuardResult]:
/// either [GuardAllow] (the navigation may proceed) or [GuardRedirect] (send the
/// user somewhere else). Concrete guards live in `guards.dart`; this file only
/// defines the shape they share.
///
/// [GuardResult] is `sealed`, so a `switch` over it is checked for
/// exhaustiveness by the compiler:
///
/// ```dart
/// final String? target = switch (route.accessGuard.evaluate(context)) {
///   GuardAllow() => null,
///   GuardRedirect(:final location) => location,
/// };
/// ```
///
/// ## Writing a guard
///
/// Extend [RouteGuard], keep it `const`, pure and synchronous, and return a
/// [GuardResult]. Anything the guard needs to know must already be on the
/// [GuardContext]; guards never read providers or await anything.
///
/// ```dart
/// class SameOutletGuard extends RouteGuard {
///   const SameOutletGuard(this.outletId);
///
///   final String outletId;
///
///   @override
///   GuardResult evaluate(GuardContext context) {
///     final session = context.session;
///     if (session == null) {
///       return GuardResult.redirect(context.gate(SystemRoutes.login));
///     }
///     return session.outletId == outletId
///         ? const GuardResult.allow()
///         : GuardResult.redirect(SystemRoutes.forbidden.path);
///   }
/// }
/// ```
///
/// See also:
///
/// * [GuardContext], everything a guard is allowed to know.
/// * `CompositeGuard`, which runs several guards and returns the first
///   redirect.
library;

import 'guard_context.dart';

/// The outcome of evaluating a [RouteGuard].
///
/// Create one with the [GuardResult.allow] or [GuardResult.redirect] factory.
/// Consume it with pattern matching on [GuardAllow] and [GuardRedirect].
sealed class GuardResult {
  const GuardResult();

  /// A result that lets the navigation proceed.
  const factory GuardResult.allow() = GuardAllow;

  /// A result that sends the user to [location] instead.
  ///
  /// [location] is a full in-app location, query string included, typically
  /// built with `GuardContext.gate` or `RouteSpec.withQuery`. [reason] is a
  /// short, stable, machine-readable cause (for example `token_expired`) for
  /// logs and tests. It is not meant to be shown to the user.
  ///
  /// ```dart
  /// GuardResult.redirect(
  ///   context.gate(SystemRoutes.login),
  ///   reason: 'not_authenticated',
  /// );
  /// ```
  const factory GuardResult.redirect(String location, {String? reason}) = GuardRedirect;
}

/// The navigation is permitted.
final class GuardAllow extends GuardResult {
  /// Creates an allow result. Prefer [GuardResult.allow].
  const GuardAllow();
}

/// The navigation is refused and the user is sent to [location] instead.
///
/// A short, stable cause for diagnostics, or `null` when none was given.
///
/// Reasons are for logs and assertions in tests, so keep them
/// machine-readable rather than user-facing.
final class GuardRedirect extends GuardResult {
  /// Creates a redirect to [location]. Prefer [GuardResult.redirect].
  final String location;
  final String? reason;

  const GuardRedirect(this.location, {this.reason});
}

/// A single, composable access rule.
///
/// Each route declares one guard on its `RouteSpec`. `RouteSpec.accessGuard`
/// then composes it with the guard of every ancestor, root first, so
/// `/orders/:orderId/refund` is checked against the `/orders` guard **and** its
/// own. A child can only ever tighten access, never widen it.
///
/// Implementations must be:
///
/// * **Pure.** The same [GuardContext] always yields the same [GuardResult].
/// * **Synchronous.** go_router runs `redirect` on every navigation, including
///   the first frame, so anything async shows up as a visible flicker.
/// * **`const`.** Guards are declared in `const` route definitions.
abstract class RouteGuard {
  /// Creates a route guard.
  const RouteGuard();

  /// Decides whether the navigation described by [context] may proceed.
  ///
  /// Returns [GuardResult.allow] to let it through, or [GuardResult.redirect]
  /// to send the user elsewhere. Must not throw for any valid context,
  /// including one with no session.
  GuardResult evaluate(GuardContext context);
}
