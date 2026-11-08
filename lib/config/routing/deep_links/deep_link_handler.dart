import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../navigation/navigation_service.dart';
import '../route_params.dart';
import '../route_registry.dart';
import '../route_spec.dart';
import '../system_modules/system_routes.dart';

/// Normalizes and validates incoming deep links before they reach the router.
///
/// go_router already handles platform deep links on its own; this exists for
/// the links it cannot see - a notification payload, a scanned QR code, a
/// custom scheme, a link from an embedded webview - and to strip the ones that
/// should never be navigable.
///
/// Everything is checked against the [RouteRegistry], so a malformed or
/// hostile link lands on 404 instead of a blank screen. It is constructed with
/// its registry (see `deepLinkHandlerProvider`) instead of reaching for a
/// global, which is also what makes [resolve] testable with a fake registry.
class DeepLinkHandler {
  DeepLinkHandler({
    required this._registry,
    NavigationService? navigation,
    this.trustedHosts = AppConstants.trustedHosts,
    this.customScheme = AppConstants.customScheme,
  }) : _navigation = navigation ?? NavigationService.instance;

  final RouteRegistry _registry;
  final NavigationService _navigation;

  /// Hosts you own. A link from anywhere else is discarded rather than
  /// followed - an app-link intent filter is not an authorization check.
  final Set<String> trustedHosts;

  final String customScheme;

  /// Feed this every externally supplied link. Returns the location that was
  /// navigated to, or null when the link was rejected.
  String? handle(String rawLink) {
    final location = resolve(rawLink);

    if (location == null) {
      _navigation.goTo(SystemRoutes.notFound, query: {RouteQuery.attempted: rawLink});
      return null;
    }

    // Straight to the router: the redirect policy still runs, so an
    // unauthenticated deep link is parked at sign-in with ?from= set and
    // resumes automatically once the user signs in.
    _navigation.goToLocation(location);
    return location;
  }

  /// Pure resolution step, separated so it can be unit tested without a router.
  @visibleForTesting
  String? resolve(String rawLink) {
    final uri = Uri.tryParse(rawLink.trim());
    if (uri == null) return null;

    final String path;
    if (uri.scheme == customScheme) {
      // `variationbd://orders/42` parses as host "orders" + path "/42", so the
      // host is the first path segment, not an authority to validate.
      path = '/${uri.host}${uri.path}';
    } else if (uri.scheme == 'https') {
      // https only, and only our hosts. `https://app.aurorapos.com@evil.com`
      // parses with host evil.com and is rejected here.
      if (!trustedHosts.contains(uri.host)) return null;
      path = uri.path.isEmpty ? '/' : uri.path;
    } else if (!uri.hasScheme && !uri.hasAuthority) {
      // An in-app relative link such as `/orders/42`. A scheme-less `//evil.com`
      // has an authority and is rejected.
      path = uri.path.isEmpty ? '/' : uri.path;
    } else {
      return null;
    }

    final spec = _registry.byLocation(path);
    if (spec == null) return null;

    // Rebuild from the resolved spec so any stray fragment, userInfo or
    // duplicated slash is dropped rather than forwarded.
    final params = spec.extractParams(path);
    final query = <String, String?>{...uri.queryParameters};
    return spec.withParamsAndQuery(params, query);
  }

  /// Builds a shareable https link for a route - receipts, order links, an
  /// invite to a staff account.
  Uri buildLink(
    RouteSpec spec, {
    Map<String, String> params = const {},
    Map<String, String?> query = const {},
    String host = AppConstants.host,
  }) {
    final location = Uri.parse(spec.withParamsAndQuery(params, query));
    return Uri(
      scheme: 'https',
      host: host,
      path: location.path,
      queryParameters: location.queryParameters.isEmpty ? null : location.queryParameters,
    );
  }
}
