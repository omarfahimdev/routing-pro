import '../../../core/constants/permissions.dart';
import '../../../features/auth/domain/auth_state.dart';
import '../route_params.dart';
import '../route_spec.dart';
import '../system_modules/system_routes.dart';
import 'guard_context.dart';
import 'route_guard.dart';

/// ================================================================================
/// The access rules themselves.
///
/// Guards are const, pure and synchronous. Each route declares one on its
/// [RouteSpec] and `RouteSpec.accessGuard` composes it with its ancestors', so a
/// child route can only ever tighten access, never widen it.
///
/// Redirect targets come from [SystemRoutes] (core), never from a feature, so
/// core keeps no dependency on any feature module.
/// ================================================================================

/// Always allows. The default for routes that declare no rule.
class AllowGuard extends RouteGuard {
  const AllowGuard();

  @override
  GuardResult evaluate(GuardContext context) => const GuardResult.allow();
}

/// Requires a live session. Unauthenticated or expired-token users are sent to
/// sign-in with the destination preserved in `?from=`.
class AuthGuard extends RouteGuard {
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

/// The inverse: sign-in and password recovery are for guests only. An
/// authenticated user who lands there goes to their landing page.
class GuestGuard extends RouteGuard {
  const GuestGuard();

  @override
  GuardResult evaluate(GuardContext context) {
    if (context.auth case Authenticated(:final session)) {
      return GuardResult.redirect(context.returnTo ?? context.homeFor(session), reason: 'already_authenticated');
    }
    return const GuardResult.allow();
  }
}

/// Requires capabilities, as `resource:action` keys.
///
/// `PermissionGuard({Permissions.viewOrders})` for all of them,
/// `PermissionGuard.any({...})` for at least one.
class PermissionGuard extends RouteGuard {
  const PermissionGuard(this.permissions, {this.requireAll = true});

  const PermissionGuard.any(this.permissions) : requireAll = false;

  final Set<String> permissions;
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

/// Requires *any* action on a resource. Useful for a section landing page whose
/// children each need their own specific action.
class ResourceGuard extends RouteGuard {
  const ResourceGuard(this.resource);

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

/// Role check by name, for the rare rule that is genuinely about who someone is
/// rather than what they may do (audit logs, impersonation, billing owner).
class RoleGuard extends RouteGuard {
  const RoleGuard(this.roles);

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
class OpenShiftGuard extends RouteGuard {
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
    //   return GuardResult.redirect(context.gate(SystemRoutes.openShift), reason: 'no_open_shift');
    // }
    return const GuardResult.allow();
  }
}

/// Blocks until the account e-mail is confirmed. [verifyAt] is where the user
/// is sent to do it - supplied by the declaring route, so core never has to
/// import a settings feature.
class EmailVerifiedGuard extends RouteGuard {
  const EmailVerifiedGuard({required this.verifyAt});

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

/// Runs guards in order and returns the first non-allow result. Declaration
/// order matters: put the cheapest and most fundamental check first.
class CompositeGuard extends RouteGuard {
  const CompositeGuard(this.guards);

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

/// ================================================================================
/// Ready-made combinations, so the same list is not re-composed at a dozen
/// declaration sites. Only const members can be used inside a `const RouteSpec`;
/// the factory methods are for non-const call sites.
/// ================================================================================
abstract final class Guards {
  const Guards._();

  static const allow = AllowGuard();
  static const auth = AuthGuard();
  static const guest = GuestGuard();
  static const openShift = OpenShiftGuard();

  /// Signed in, allowed to run the till, and standing at an open register.
  static const selling = CompositeGuard([
    AuthGuard(),
    PermissionGuard({Permissions.operateTerminal}),
    OpenShiftGuard(),
  ]);

  /// Signed in *and* holding every one of [permissions].
  static RouteGuard permission(Set<String> permissions) =>
      CompositeGuard([const AuthGuard(), PermissionGuard(permissions)]);

  static RouteGuard anyPermission(Set<String> permissions) =>
      CompositeGuard([const AuthGuard(), PermissionGuard.any(permissions)]);

  static RouteGuard role(Set<String> roles) => CompositeGuard([const AuthGuard(), RoleGuard(roles)]);
}
