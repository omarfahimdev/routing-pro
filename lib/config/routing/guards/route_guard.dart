import 'guard_context.dart';

/// ================================================================================
/// THE OUTCOME OF A GUARD CHECK.
/// ================================================================================
sealed class GuardResult {
  const GuardResult();

  const factory GuardResult.allow() = GuardAllow;

  const factory GuardResult.redirect(String location, {String? reason}) =
      GuardRedirect;
}

final class GuardAllow extends GuardResult {
  const GuardAllow();
}

final class GuardRedirect extends GuardResult {
  const GuardRedirect(this.location, {this.reason});

  final String location;
  final String? reason;

  @override
  String toString() => 'GuardRedirect($location, reason: $reason)';
}

/// ================================================================================
/// A SINGLE, COMPOSABLE ACCESS RULE.
///
/// Each route declares its guard on its `RouteSpec`, and `RouteSpec.accessGuard`
/// composes it with every ancestor's, so `/orders/:id/refund` is checked against
/// the `/orders` guard *and* its own. A child can only ever tighten access,
/// never widen it.
/// ================================================================================
abstract class RouteGuard {
  const RouteGuard();

  GuardResult evaluate(GuardContext context);
}
