import 'package:go_router/go_router.dart';

import 'route_module.dart';
import 'route_spec.dart';

/// LOOKUP + VALIDATION OVER EVERY REGISTERED [RouteSpec].
///
/// Built once from the modules. This is what the enum's static maps were doing
/// (`byPattern`, `byName`, `byLocation`), except it is an injectable instance:
/// testable with a fake module list, and no global mutable state.
///
/// Misconfiguration throws at startup instead of surfacing as a wrong screen
/// in production.
final class RouteRegistry {
  final List<RouteSpec> specs;
  final Map<String, RouteSpec> _byPath;
  final Map<String, RouteSpec> _byName;

  RouteRegistry._(this.specs, this._byPath, this._byName);

  factory RouteRegistry.of(Iterable<RouteModule> modules) {
    final byPath = <String, RouteSpec>{};
    final byName = <String, RouteSpec>{};

    for (final module in modules) {
      for (final spec in module.specs) {
        _validate(spec);

        final samePath = byPath[spec.path];
        if (samePath != null && !identical(samePath, spec)) {
          throw StateError('Duplicate route path "${spec.path}": ${samePath.name} and ${spec.name}');
        }
        final sameName = byName[spec.name];
        if (sameName != null && !identical(sameName, spec)) {
          throw StateError('Duplicate route name "${spec.name}": ${sameName.path} and ${spec.path}');
        }

        byPath[spec.path] = spec;
        byName[spec.name] = spec;
      }
    }

    for (final spec in byPath.values) {
      final parent = spec.parent;
      if (parent != null && !byPath.containsKey(parent.path)) {
        throw StateError('${spec.name} has parent ${parent.name} which no module registers');
      }
    }

    return RouteRegistry._(List.unmodifiable(byPath.values), Map.unmodifiable(byPath), Map.unmodifiable(byName));
  }

  /// Exact pattern lookup. Feed it `GoRouterState.fullPath`.
  RouteSpec? byPattern(String? pattern) => pattern == null ? null : _byPath[pattern];

  RouteSpec? byName(String? name) => name == null ? null : _byName[name];

  /// Resolves a concrete location such as `/products/42`. The most literal
  /// match wins, so `/products/new` beats `/products/:productId`.
  RouteSpec? byLocation(String location) {
    final path = location.split('?').first;
    final exact = _byPath[path];
    if (exact != null) return exact;

    RouteSpec? best;
    for (final spec in specs) {
      if (!spec.matches(path)) continue;
      if (best == null || spec.literalSegments > best.literalSegments) {
        best = spec;
      }
    }
    return best;
  }

  RouteSpec? resolve(GoRouterState state) => byPattern(state.fullPath) ?? byLocation(state.matchedLocation);

  static void _validate(RouteSpec spec) {
    if (spec.name.isEmpty) {
      throw StateError('Route with segment "${spec.segment}" has no name');
    }

    final isRoot = spec.parent == null;
    if (isRoot && !spec.segment.startsWith('/')) {
      throw StateError('Root route ${spec.name} must start with "/": "${spec.segment}"');
    }
    if (!isRoot && (spec.segment.isEmpty || spec.segment.startsWith('/'))) {
      throw StateError('Child route ${spec.name} must be a relative segment: "${spec.segment}"');
    }
  }
}
