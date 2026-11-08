import 'package:flutter/foundation.dart';

import '../../../features/auth/domain/auth_state.dart';
import '../../../features/auth/domain/session.dart';
import '../route_params.dart';
import '../route_registry.dart';
import '../route_spec.dart';
import '../system_modules/system_routes.dart';

/// Where a signed-in user lands. Injected because it depends on the nav
/// configuration (first visible tab), which core must not import.
typedef LandingResolver = String Function(Session session);

/// ================================================================================
/// EVERYTHING A GUARD IS ALLOWED TO KNOW.
///
/// Deliberately free of BuildContext and Ref: guards are pure, synchronous and
/// unit-testable. go_router's redirect runs on every navigation including the
/// first frame, so anything async here shows up as a visible flicker.
/// ================================================================================
@immutable
class GuardContext {
  const GuardContext({
    required this.auth,
    required this.uri,
    required this.matchedLocation,
    required this.homeFor,
    this.route,
  });

  /// Test helper: build a context straight from a location string.
  factory GuardContext.parse(
    String location,
    AuthState auth, {
    required RouteRegistry registry,
    LandingResolver? homeFor,
  }) {
    final uri = Uri.parse(location);
    return GuardContext(
      auth: auth,
      uri: uri,
      matchedLocation: uri.path,
      route: registry.byLocation(uri.path),
      homeFor: homeFor ?? _fallbackHome,
    );
  }

  final AuthState auth;

  /// Full location including the query string.
  final Uri uri;

  /// Concrete matched path, e.g. `/products/42`.
  final String matchedLocation;

  /// The resolved route, or null when the URL matches nothing.
  final RouteSpec? route;

  final LandingResolver homeFor;

  static String _fallbackHome(Session session) => '/';

  Session? get session => auth.sessionOrNull;
  bool get isAuthenticated => auth.isAuthenticated;

  /// ================================================================================
  /// REDIRECT, BUT REMEMBER WHERE THE USER WAS GOING.
  ///
  /// Builds `/login?from=%2Fproducts%2F42` so the gate can hand the user back to
  /// where they were going. Gates themselves are never recorded as a
  /// destination - that is how redirect loops start.
  /// ================================================================================
  String gate(RouteSpec target) {
    final current = uri.toString();
    if (!_isReturnable(uri.path) || current.isEmpty) return target.path;
    return Uri(path: target.path, queryParameters: {RouteQuery.from: current}).toString();
  }

  /// ========================================================                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           ========================
  /// OPEN REDIRECT PROTECTION.
  ///
  /// Reads `?from=` defensively. On web this value is attacker-controllable
  /// (phishing link -> your real `/login?from=//evil.example` -> redirect to
  /// their clone), so anything carrying a scheme, an authority, or a
  /// protocol-relative `//` prefix is discarded.
  /// ================================================================================
  String? get returnTo => sanitizeReturnTo(uri.queryParameters[RouteQuery.from]);

  /// Validates a `?from=` value. Use this - never the raw query string - for
  /// every screen that navigates to it (lock, open-shift, ...), not only the
  /// redirect policy.
  static String? sanitizeReturnTo(String? candidate) {
    // queryParameters is already percent-decoded; decoding again would throw on
    // a literal '%' and would defeat the checks below.
    if (candidate == null || candidate.isEmpty) return null;
    if (!candidate.startsWith('/') || candidate.startsWith('//')) return null;

    final target = Uri.tryParse(candidate);
    if (target == null || target.hasScheme || target.hasAuthority) return null;
    if (!_isReturnable(target.path)) return null;

    return candidate;
  }

  /// Never save a gate (splash, login, lock, error pages) as a return target.
  static bool _isReturnable(String path) {
    if (path.isEmpty || path == '/') return false;
    return !SystemRoutes.isGate(path);
  }
}
