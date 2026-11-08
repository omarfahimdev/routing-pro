import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'guards/guards.dart';
import 'guards/route_guard.dart';
import 'transitions/route_transitions.dart';

/// ONE ROUTE'S DECLARATION, OWNED BY THE FEATURE THAT SERVES IT.
///
/// Replaces the single `AppRoute` enum. A spec is plain const data:
/// where it lives (segment + parent), how it is guarded, how it animates.
/// It knows nothing about icons or tabs - navigation chrome is a separate
/// concern (see `NavDestination`).
///
/// A child's absolute path is DERIVED from its parent, so a path can never
/// drift from the tree, and the `GoRoute` is built from the same object
/// (see [route]) so the "child declared as `/edit`" bug cannot be written.
@immutable
final class RouteSpec {
  /// A top-level path. [segment] is absolute: `/orders`.
  const RouteSpec.root(
    this.segment, {
    required this.name,
    this.title = '',
    this.guard = const AllowGuard(),
    this.transition = TransitionPreset.adaptive,
    this.fullscreen = false,
  }) : parent = null;

  /// A nested path. [segment] is relative: `:orderId`, `refund`.
  const RouteSpec.child(
    RouteSpec this.parent,
    this.segment, {
    required this.name,
    this.title = '',
    this.guard = const AllowGuard(),
    this.transition = TransitionPreset.adaptive,
    this.fullscreen = false,
  });

  /// Absolute for roots, relative for children. Exactly what `GoRoute.path` wants.
  final String segment;

  /// go_router route name. Unique across the app (the registry enforces it).
  final String name;

  /// Browser tab title, app bar title, Android recent label.
  final String title;

  /// This route's own rule. [accessGuard] composes it with its ancestors'.
  final RouteGuard guard;

  final TransitionPreset transition;

  /// Rendered on the root navigator, covering the shell chrome.
  final bool fullscreen;

  final RouteSpec? parent;

  // ---------------------------------------------------------------- identity

  /// Full absolute path, `:params` included.
  String get path {
    final p = parent;
    return p == null ? segment : '${p.path}/$segment';
  }

  /// PII-free screen name for analytics: `orderDetail` -> `order_detail`.
  String get analyticsId => name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  /// Root-first chain ending in this spec.
  List<RouteSpec> get ancestry {
    final chain = <RouteSpec>[];
    for (RouteSpec? current = this; current != null; current = current.parent) {
      chain.insert(0, current);
    }
    return chain;
  }

  /// Number of literal (non-param) segments - used to rank competing matches.
  int get literalSegments => _segments(path).where((s) => !s.startsWith(':')).length;

  // ------------------------------------------------------------------ access

  /// This route's guard composed with every ancestor's, root first, de-duplicated.
  ///
  /// A child can only tighten access, never widen it. The chain is tiny (depth
  /// is 2-3) and the guards are const, so this is cheap enough to compute per
  /// navigation without a mutable static cache.
  RouteGuard get accessGuard {
    final chain = <RouteGuard>[];
    void add(RouteGuard guard) {
      if (!chain.contains(guard)) chain.add(guard);
    }

    for (final spec in ancestry) {
      final guard = spec.guard;
      if (guard is AllowGuard) continue;
      if (guard is CompositeGuard) {
        guard.guards.forEach(add);
      } else {
        add(guard);
      }
    }

    return switch (chain.length) {
      0 => const AllowGuard(),
      1 => chain.first,
      _ => CompositeGuard(List.unmodifiable(chain)),
    };
  }

  // ----------------------------------------------------------- path building

  /// `OrdersRoutes.detail.withParams({'orderId': '42'})` -> `/orders/42`.
  String withParams(Map<String, String> params) {
    final result = path
        .split('/')
        .map((segment) {
          if (!segment.startsWith(':')) return segment;
          final value = params[segment.substring(1)];
          return value == null ? segment : Uri.encodeComponent(value);
        })
        .join('/');
    assert(!result.contains(':'), 'Unfilled path parameter in $name: $result (given ${params.keys})');
    return result;
  }

  String withQuery(Map<String, String?> query) => _build(path, query);

  String withParamsAndQuery(Map<String, String> params, Map<String, String?> query) =>
      _build(withParams(params), query);

  static String _build(String base, Map<String, String?> query) {
    final entries = query.entries.where((e) => e.value != null && e.value!.isNotEmpty);
    if (entries.isEmpty) return base;
    return Uri(path: base, queryParameters: {for (final e in entries) e.key: e.value!}).toString();
  }

  // ---------------------------------------------------------------- matching

  /// Does a concrete location match this pattern?
  bool matches(String location) {
    final pattern = _segments(path);
    final actual = _segments(location.split('?').first);
    if (pattern.length != actual.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (pattern[i].startsWith(':')) continue;
      if (pattern[i] != actual[i]) return false;
    }
    return true;
  }

  /// `/orders/42` -> `{'orderId': '42'}`.
  Map<String, String> extractParams(String location) {
    final params = <String, String>{};
    final pattern = _segments(path);
    final actual = _segments(location.split('?').first);
    if (pattern.length != actual.length) return params;
    for (var i = 0; i < pattern.length; i++) {
      if (pattern[i].startsWith(':')) params[pattern[i].substring(1)] = Uri.decodeComponent(actual[i]);
    }
    return params;
  }

  static List<String> _segments(String path) => path.split('/').where((s) => s.isNotEmpty).toList();

  // ---------------------------------------------------------------- go_router

  Page<void> page(GoRouterState state, Widget child) => RouteTransitions.buildPage<void>(
    state: state,
    child: child,
    title: title,
    preset: transition,
    fullscreenDialog: fullscreen,
  );

  /// The one way to turn a spec into a `GoRoute`. Path, name, title and
  /// transition always come from the spec, so they cannot disagree with the
  /// guards, the shell or the analytics.
  GoRoute route({
    required Widget Function(BuildContext context, GoRouterState state) builder,
    List<RouteBase> routes = const <RouteBase>[],
    GlobalKey<NavigatorState>? parentNavigatorKey,
    ExitCallback? onExit,
  }) => GoRoute(
    path: segment,
    name: name,
    parentNavigatorKey: parentNavigatorKey,
    onExit: onExit,
    pageBuilder: (context, state) => page(state, builder(context, state)),
    routes: routes,
  );

  @override
  String toString() => 'RouteSpec($name, $path)';
}

/// Reads a required path parameter, failing loudly in debug.
extension GoRouterStateX on GoRouterState {
  String requireParam(String key) {
    final value = pathParameters[key];
    assert(value != null, 'Missing path parameter "$key" on $matchedLocation');
    return value ?? '';
  }

  String? query(String key) {
    final value = uri.queryParameters[key];
    return (value == null || value.isEmpty) ? null : value;
  }
}
