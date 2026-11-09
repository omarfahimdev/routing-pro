/// Route guards: the pure, composable access rules behind every route.
///
/// A guard answers one question: *may this navigation proceed?* It receives a
/// [GuardContext] and returns a [GuardResult], either allow or redirect to
/// another location. Guards never touch `BuildContext` or `Ref` and never do
/// async work, so they run synchronously inside go_router's `redirect`, are
/// `const`, and can be unit tested with `GuardContext.parse`.
///
/// ## Composition
///
/// Each route declares one guard on its [RouteSpec]. `RouteSpec.accessGuard`
/// then composes it with the guards of every ancestor route, root first, so a
/// child can only ever **tighten** access, never widen it.
///
/// ```dart
///  orders requires order:read; /orders/:id/refund adds order:refund.
///  Visiting the refund route evaluates both, in that order.
/// ```
///
/// ## Choosing a guard
///
/// | Need                                  | Use                                |
/// | ------------------------------------- | ---------------------------------- |
/// | Signed-in user                        | [Guards.auth]                      |
/// | Signed-out users only (sign-in pages) | [Guards.guest]                     |
/// | Every one of several permissions      | [Guards.permission]                |
/// | At least one of several permissions   | [Guards.anyPermission]             |
/// | Any action on a resource              | [ResourceGuard]                    |
/// | A specific role                       | [Guards.role], used sparingly      |
/// | Till access with an open shift        | [Guards.selling]                   |
///
/// ## Redirect targets
///
/// Redirect targets come from [SystemRoutes], which lives in core. A guard
/// never names a feature route, so core has no dependency on any feature
/// module. Where a guard needs a feature-owned destination, the declaring
/// route supplies it, as with [EmailVerifiedGuard.verifyAt].
///
/// ## Example
///
/// ```dart
/// refund(
///   '/orders/:orderId/refund',
///   guard: PermissionGuard({Permissions.issueRefund}),
/// ),
///
/// // Evaluating a guard directly, for example in a unit test:
/// final context = GuardContext.parse('/orders/42/refund', authState);
/// final result = Guards.permission({Permissions.issueRefund}).evaluate(context);
/// ```
///
/// See also:
///
/// * [RouteGuard], the base class every guard extends.
/// * [GuardContext], everything a guard is allowed to know.
/// * `RedirectPolicy`, which runs the composed guard for each navigation.
library;

import '../../../core/constants/permissions.dart';
import '../../../features/auth/domain/auth_state.dart';
import '../route_params.dart';
import '../route_spec.dart';
import '../system_modules/system_routes.dart';
import 'guard_context.dart';
import 'route_guard.dart';

/// A guard that always allows navigation.
///
/// This is the default for routes that declare no rule. [RouteSpec.accessGuard]
/// skips it when composing a chain, so declaring it explicitly has no cost.
class AllowGuard extends RouteGuard {
  /// Creates a guard that allows every navigation.
  const AllowGuard();

  @override
  GuardResult evaluate(GuardContext context) => const GuardResult.allow();
}

/// Requires a live, unexpired session.
///
/// A signed-out user, or one whose access token has expired, is redirected to
/// [SystemRoutes.login] with the attempted location preserved in `?from=`, so
/// the sign-in screen can return them to where they were going.
///
/// | Condition             | Redirect reason       |
/// | --------------------- | --------------------- |
/// | No session            | `not_authenticated`   |
/// | Access token expired  | `token_expired`       |
///
/// ```dart
/// dashboard('/dashboard', guard: Guards.auth);
/// ```
class AuthGuard extends RouteGuard {
  /// Creates a guard that requires a live session.
  const AuthGuard();

  @override
  GuardResult evaluate(GuardContext context) {
    final session = context.session;
    if (session == null) {
      return GuardResult.redirect(context.gate(SystemRoutes.login), reason: 'not_authenticated');
    }
    if (session.isAccessTokenExpired) {
      return GuardResult.redirect(context.gate(SystemRoutes.login), reason: 'token_expired');
    }
    return const GuardResult.allow();
  }
}

/// Admits guests only: the inverse of [AuthGuard].
///
/// Sign-in and password recovery use this. A user who is already authenticated
/// and lands on one of those pages is redirected to the validated `?from=`
/// destination if present, otherwise to their landing page from
/// [GuardContext.homeFor].
///
/// A *locked* session is deliberately not redirected here. The redirect policy
/// handles the lock state before any route guard runs.
///
/// ```dart
/// login('/login', guard: Guards.guest);
/// ```
class GuestGuard extends RouteGuard {
  /// Creates a guard that admits only users who are not signed in.
  const GuestGuard();

  @override
  GuardResult evaluate(GuardContext context) {
    if (context.auth case Authenticated(:final session)) {
      return GuardResult.redirect(context.returnTo ?? context.homeFor(session), reason: 'already_authenticated');
    }
    return const GuardResult.allow();
  }
}

/// Requires capabilities, expressed as `resource:action` keys.
///
/// By default the session must hold **every** key in [permissions]. Use
/// [PermissionGuard.any] when holding **at least one** is enough. A session
/// that lacks the capability is redirected to [SystemRoutes.forbidden], with
/// the attempted location attached for display.
///
/// This guard checks permissions only. Compose it after [AuthGuard], or build
/// it through [Guards.permission], so expired tokens are rejected first.
///
/// ```dart
/// // Every permission is required.
/// const PermissionGuard({Permissions.viewOrders, Permissions.issueRefund});
///
/// // One of them is enough.
/// const PermissionGuard.any({Permissions.viewOrders, Permissions.viewReports});
/// ```
class PermissionGuard extends RouteGuard {
  /// Creates a guard requiring [permissions].
  ///
  /// When [requireAll] is `true` (the default) every permission is required;
  /// when `false`, at least one is.
  const PermissionGuard(this.permissions, {this.requireAll = true});

  /// Creates a guard that is satisfied by holding **any one** of [permissions].
  const PermissionGuard.any(this.permissions) : requireAll = false;

  /// The `resource:action` keys this guard checks.
  final Set<String> permissions;

  /// Whether every key in [permissions] is required, rather than just one.
  final bool requireAll;

  @override
  GuardResult evaluate(GuardContext context) {
    final session = context.session;
    if (session == null) {
      return GuardResult.redirect(context.gate(SystemRoutes.login), reason: 'not_authenticated');
    }

    final granted = requireAll ? session.canAll(permissions) : session.canAny(permissions);
    if (!granted) {
      return GuardResult.redirect(
        SystemRoutes.forbidden.withQuery({RouteQuery.attempted: context.uri.toString()}),
        reason: 'missing_permission:${permissions.join(',')}',
      );
    }
    return const GuardResult.allow();
  }
}

/// Requires **any** action on a [resource].
///
/// Suited to a section landing page whose children each demand a specific
/// action: the section opens for anyone who can do something there, and each
/// child narrows it further.
///
/// ```dart
/// // Holding order:read, order:refund or any other order:* key passes.
/// const ResourceGuard('order');
/// ```
class ResourceGuard extends RouteGuard {
  /// Creates a guard requiring any action on [resource].
  const ResourceGuard(this.resource);

  /// The resource name, the part of the key before the colon (`order` in
  /// `order:read`).
  final String resource;

  @override
  GuardResult evaluate(GuardContext context) {
    final session = context.session;
    if (session == null) {
      return GuardResult.redirect(context.gate(SystemRoutes.login), reason: 'not_authenticated');
    }
    if (!session.canAccess(resource)) {
      return GuardResult.redirect(
        SystemRoutes.forbidden.withQuery({RouteQuery.attempted: context.uri.toString()}),
        reason: 'no_access_to:$resource',
      );
    }
    return const GuardResult.allow();
  }
}

/// Requires one of a set of roles, by name.
///
/// Prefer [PermissionGuard]. Reserve this for rules that are genuinely about
/// who someone is rather than what they may do, such as audit logs,
/// impersonation or billing ownership. Role names arrive from the API, so a
/// renamed role silently locks users out.
///
/// ```dart
/// const RoleGuard({'owner', 'billing_admin'});
/// ```
class RoleGuard extends RouteGuard {
  /// Creates a guard satisfied by holding **any one** of [roles].
  const RoleGuard(this.roles);

  /// The role names, any one of which grants access.
  final Set<String> roles;

  @override
  GuardResult evaluate(GuardContext context) {
    final session = context.session;
    if (session == null) {
      return GuardResult.redirect(context.gate(SystemRoutes.login), reason: 'not_authenticated');
    }
    if (!session.hasAnyRole(roles)) {
      return GuardResult.redirect(
        SystemRoutes.forbidden.withQuery({RouteQuery.attempted: context.uri.toString()}),
        reason: 'wrong_role',
      );
    }
    return const GuardResult.allow();
  }
}

/// POS-specific: no selling until the register shift is open.
///
/// **Currently a stub.** It checks for a session and then allows, because the
/// shift feature has not landed. Guards are pure, so the shift state must be
/// readable from [AuthState] or the session rather than from a provider.
///
/// Once available, a missing shift redirects to [SystemRoutes.openShift] with
/// the destination preserved, so the cashier lands back at the till after
/// counting their float.
///
/// ```dart
/// checkout('/checkout', guard: Guards.selling);
/// ```
class OpenShiftGuard extends RouteGuard {
  /// Creates a guard that requires an open register shift.
  const OpenShiftGuard();

  @override
  GuardResult evaluate(GuardContext context) {
    final session = context.session;
    if (session == null) {
      return GuardResult.redirect(context.gate(SystemRoutes.login), reason: 'not_authenticated');
    }
    // TODO(shift): gate on the open-shift state once the shift feature lands.
    // Guards are pure, so the shift state must be readable from AuthState or
    // Session - not from a provider.
    // if (!session.hasOpenShift) {
    //   return GuardResult.redirect(
    //     context.gate(SystemRoutes.openShift),
    //     reason: 'no_open_shift',
    //   );
    // }
    return const GuardResult.allow();
  }
}

/// Blocks until the account e-mail address is confirmed.
///
/// The destination for verification is supplied by the declaring route through
/// [verifyAt], so core never imports a settings feature. [verifyAt] must not
/// itself be behind this guard, or the redirect loops.
///
/// ```dart
/// payouts(
///   '/payouts',
///   guard: EmailVerifiedGuard(verifyAt: SettingsRoutes.profile),
/// ),
/// ```
class EmailVerifiedGuard extends RouteGuard {
  /// Creates a guard that redirects unverified users to [verifyAt].
  const EmailVerifiedGuard({required this.verifyAt});

  /// The route where the user can confirm their e-mail address.
  final RouteSpec verifyAt;

  @override
  GuardResult evaluate(GuardContext context) {
    final session = context.session;
    if (session == null) {
      return GuardResult.redirect(context.gate(SystemRoutes.login), reason: 'not_authenticated');
    }
    if (!session.isEmailVerified) {
      return GuardResult.redirect(verifyAt.path, reason: 'email_unverified');
    }
    return const GuardResult.allow();
  }
}

/// Runs several guards in order and returns the first redirect.
///
/// Evaluation stops at the first guard that redirects; if none does, the result
/// is allow. Declaration order matters: put the cheapest and most fundamental
/// check first, usually [AuthGuard], so later guards can assume a session
/// exists.
///
/// ```dart
/// const CompositeGuard([
///   AuthGuard(),
///   PermissionGuard({Permissions.viewReports}),
/// ]);
/// ```
class CompositeGuard extends RouteGuard {
  /// Creates a guard that evaluates [guards] in order.
  const CompositeGuard(this.guards);

  /// The guards to run, in evaluation order.
  final List<RouteGuard> guards;

  @override
  GuardResult evaluate(GuardContext context) {
    for (final guard in guards) {
      final result = guard.evaluate(context);
      if (result is GuardRedirect) return result;
    }
    return const GuardResult.allow();
  }
}

/// Ready-made guard combinations, so the same list is not re-composed at a
/// dozen declaration sites.
///
/// Only the `const` members can be used inside a `const` route declaration.
/// The static methods build a new guard each call and suit non-const call
/// sites.
///
/// ```dart
/// products('/products', guard: Guards.auth),
/// reports('/reports', guard: Guards.permission({Permissions.viewReports})),
/// ```
abstract final class Guards {
  const Guards._();

  /// Allows everything. Equivalent to declaring no guard.
  static const allow = AllowGuard();

  /// Requires a live session. See [AuthGuard].
  static const auth = AuthGuard();

  /// Admits guests only. See [GuestGuard].
  static const guest = GuestGuard();

  /// Requires an open register shift. See [OpenShiftGuard].
  static const openShift = OpenShiftGuard();

  /// Signed in, allowed to run the till, and standing at an open register.
  ///
  /// Checks run in this order: session, `operateTerminal` permission, open
  /// shift.
  static const selling = CompositeGuard([
    AuthGuard(),
    PermissionGuard({Permissions.operateTerminal}),
    OpenShiftGuard(),
  ]);

  /// Signed in **and** holding every one of [permissions].
  ///
  /// The usual choice when declaring a route.
  ///
  /// ```dart
  /// Guards.permission({Permissions.viewOrders});
  /// ```
  static RouteGuard permission(Set<String> permissions) =>
      CompositeGuard([const AuthGuard(), PermissionGuard(permissions)]);

  /// Signed in **and** holding at least one of [permissions].
  ///
  /// ```dart
  /// Guards.anyPermission({Permissions.viewOrders, Permissions.viewReports});
  /// ```
  static RouteGuard anyPermission(Set<String> permissions) =>
      CompositeGuard([const AuthGuard(), PermissionGuard.any(permissions)]);

  /// Signed in **and** holding at least one of [roles].
  ///
  /// ```dart
  /// Guards.role({'owner'});
  /// ```
  static RouteGuard role(Set<String> roles) => CompositeGuard([const AuthGuard(), RoleGuard(roles)]);
}
