/// The read-only view of the world that a route guard is allowed to see.
///
/// [GuardContext] bundles the current [AuthState], the location being
/// navigated to and the resolved route into one immutable value. It is
/// deliberately free of `BuildContext` and `Ref`: guards are pure, synchronous
/// and unit-testable. go_router runs `redirect` on every navigation, including
/// the first frame, so anything asynchronous here would show up as a visible
/// flicker.
///
/// It also owns the two operations every redirect needs, and which are easy to
/// get wrong:
///
/// * [GuardContext.gate] sends the user to a gate screen (sign-in, lock) while
///   remembering where they were going.
/// * [GuardContext.returnTo] and [GuardContext.sanitizeReturnTo] read that
///   destination back **safely**, because on web the `?from=` value is
///   attacker-controllable.
///
/// ## Example
///
/// ```dart
/// // In a unit test: build a context without a router or widget tree.
/// final context = GuardContext.parse(
///   '/orders/42?status=refunded',
///   const AuthState.unauthenticated(),
///   registry: registry,
/// );
///
/// context.gate(SystemRoutes.login);
/// '/login?from=%2Forders%2F42%3Fstatus%3Drefunded'
/// ```
///
/// See also:
///
/// * [RouteGuard], which consumes a [GuardContext].
/// * `RedirectPolicy`, which builds one for every navigation.
library;

import 'package:flutter/foundation.dart';

import '../../../features/auth/domain/auth_state.dart';
import '../../../features/auth/domain/session.dart';
import '../route_params.dart';
import '../route_registry.dart';
import '../route_spec.dart';
import '../system_modules/system_routes.dart';

/// Resolves the location a signed-in [Session] should land on.
///
/// Injected into [GuardContext] rather than hard-coded, because the answer
/// depends on the navigation configuration (the first tab the session may see),
/// which core must not import.
///
/// ```dart
/// String landing(Session session) =>
///     navigation.firstVisibleTab(session)?.path ?? SystemRoutes.forbidden.path;
/// ```
typedef LandingResolver = String Function(Session session);

/// Everything a guard is allowed to know about a navigation attempt.
///
/// Instances are immutable and cheap: the redirect policy builds a new one on
/// every navigation.
@immutable
class GuardContext {
  /// The current authentication state.
  final AuthState auth;

  /// The full location being navigated to, including the query string.
  final Uri uri;

  /// The concrete matched path, without the query string, for example
  /// `/products/42`.
  final String matchedLocation;

  /// Resolves where a signed-in session lands, for example after leaving a
  /// guest-only page.
  final LandingResolver homeFor;

  /// The route [matchedLocation] resolved to, or `null` when the URL matches
  /// nothing.
  ///
  /// A `null` route is not an error here. The redirect policy leaves it alone
  /// so go_router's `onException` handler can show the not-found page.
  final RouteSpec? route;

  /// Creates a context for a navigation attempt.
  const GuardContext({
    required this.auth,
    required this.uri,
    required this.matchedLocation,
    required this.homeFor,
    this.route,
  });

  /// Builds a context straight from a [location] string.
  ///
  /// Intended for tests. The route is resolved through [registry], and
  /// [matchedLocation] is the path of [location] without its query string.
  ///
  /// When [homeFor] is omitted, signed-in users resolve to `/`, which is not a
  /// real landing page. Pass a resolver in any test that asserts on where an
  /// authenticated user is sent.
  ///
  /// ```dart
  /// final context = GuardContext.parse(
  ///   '/products/42',
  ///   AuthState.authenticated(session: session),
  ///   registry: registry,
  ///   homeFor: (_) => '/dashboard',
  /// );
  /// ```
  @visibleForTesting
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

  static String _fallbackHome(Session session) => '/';

  /// The current [Session], or `null` when no user is signed in.
  ///
  /// Also non-null while the terminal is locked. See [AuthState.sessionOrNull].
  Session? get session => auth.sessionOrNull;

  /// Whether a user is signed in **and** unlocked.
  bool get isAuthenticated => auth.isAuthenticated;

  /// Returns the location of [target] with the current destination attached as
  /// `?from=`, so the gate can send the user back once it is satisfied.
  ///
  /// If the current location is itself a gate (splash, sign-in, lock, an error
  /// page) or the root, nothing is recorded and the plain path of [target] is
  /// returned. Recording a gate as a destination is how redirect loops start.
  ///
  /// The destination is percent-encoded, query string included:
  ///
  /// ```dart
  /// // Attempting /products/42 while signed out:
  /// context.gate(SystemRoutes.login); // '/login?from=%2Fproducts%2F42'
  ///
  /// // Attempting the login page itself:
  /// context.gate(SystemRoutes.login); // '/login'
  /// ```
  String gate(RouteSpec target) {
    if (!_isReturnable(uri.path)) return target.path;
    return Uri(path: target.path, queryParameters: {RouteQuery.from: uri.toString()}).toString();
  }

  /// The validated `?from=` destination of the current [uri], or `null`.
  ///
  /// Reads the value defensively. On web it is attacker-controllable: a
  /// phishing link such as `https://app.example/login?from=//evil.example`
  /// would otherwise send the user to a look-alike site right after they sign
  /// in to the real one. See [sanitizeReturnTo] for the exact rules.
  ///
  /// ```dart
  /// // /login?from=%2Forders%2F42
  /// context.returnTo; // '/orders/42'
  ///
  /// // /login?from=//evil.example
  /// context.returnTo; // null
  /// ```
  String? get returnTo => sanitizeReturnTo(uri.queryParameters[RouteQuery.from]);

  /// Validates a raw `?from=` value and returns it only if it is safe to
  /// navigate to.
  ///
  /// Use this, and never the raw query string, in **every** place that
  /// navigates to a return target: the lock screen and the open-shift screen as
  /// well as the redirect policy.
  ///
  /// A value is accepted only if it is an in-app path. Everything else yields
  /// `null`:
  ///
  /// | Candidate                 | Result   | Why                              |
  /// | ------------------------- | -------- | -------------------------------- |
  /// | `/orders/42?status=open`  | accepted | in-app path                      |
  /// | `null` or empty           | `null`   | nothing to return to             |
  /// | `https://evil.example`    | `null`   | does not start with `/`          |
  /// | `//evil.example`          | `null`   | protocol-relative URL            |
  /// | `/\evil.example`          | `null`   | browsers read `\` as `/`         |
  /// | `/login`, `/lock`, ...    | `null`   | a gate, which would cause a loop |
  /// | `/`                       | `null`   | root carries no destination      |
  ///
  /// [candidate] must already be percent-decoded, as `Uri.queryParameters`
  /// returns it. Decoding again would throw on a literal `%` and would undo the
  /// checks below.
  ///
  /// ```dart
  /// final target = GuardContext.sanitizeReturnTo(state.query(RouteQuery.from));
  /// context.go(target ?? homePath);
  /// ```
  static String? sanitizeReturnTo(String? candidate) {
    if (candidate == null || candidate.isEmpty) return null;
    if (!candidate.startsWith('/') || candidate.startsWith('//')) return null;
    if (_unsafeCharacters.hasMatch(candidate)) return null;

    final target = Uri.tryParse(candidate);
    if (target == null || target.hasScheme || target.hasAuthority) return null;
    if (!_isReturnable(target.path)) return null;

    return candidate;
  }

  /// Backslashes and ASCII control characters (including CR and LF).
  ///
  /// Browsers normalise `\` to `/`, which turns `/\evil.example` into the
  /// protocol-relative `//evil.example`. Control characters are rejected so a
  /// value can never smuggle a line break into a log line or header.
  static final RegExp _unsafeCharacters = RegExp(r'[\\\x00-\x1F\x7F]');

  /// Whether [path] may be stored as a return destination.
  ///
  /// Gates (splash, sign-in, lock, error pages) and the root never are, because
  /// returning to one would loop straight back into the redirect that sent the
  /// user there.
  static bool _isReturnable(String path) {
    if (path.isEmpty || path == '/') return false;
    return !SystemRoutes.isGate(path);
  }
}
