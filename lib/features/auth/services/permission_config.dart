import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/permissions.dart';
import '../application/auth_controller.dart';
import '../domain/permission_model.dart';
import '../domain/role_model.dart';
import '../domain/session.dart';
import '../domain/user_model.dart';

/// Answers "may this user do X?" for widgets.
///
/// Roles and permissions come from the API, so everything here works on
/// `resource:action` strings rather than an enum. A new permission on the
/// server needs no app release.
///
/// The router asks the same question through the session's own helpers
/// ([Session.can] and friends). This service is the widget-facing form of it,
/// and both read the identical set of keys.
///
/// A user's effective permissions are the union of the permissions of every
/// role in [roles] and the permissions in [directPermissions].
///
/// ## Example
///
/// ```dart
/// // In a widget, through the provider:
/// final permissions = ref.watch(permissionServiceProvider);
/// if (permissions.canUpdate('product')) {
///   // Show the edit button.
/// }
///
/// // Inspecting somebody else's access on a staff screen:
/// final theirs = PermissionService.fromUser(user);
/// final actions = theirs.getResourceActions('order'); // ['read', 'refund']
/// ```
///
/// See also:
///
/// * [permissionServiceProvider], which follows the signed-in session.
/// * [Session], the same checks for non-widget code such as route guards.
class PermissionService {
  /// Creates a service from [roles] and [directPermissions].
  ///
  /// Both default to empty, which yields a service that grants nothing.
  const PermissionService({this.roles = const [], this.directPermissions = const []});

  /// Creates a service from the signed-in [session].
  ///
  /// The usual case, and what the providers below use. A `null` session yields
  /// a service that grants nothing.
  factory PermissionService.fromSession(Session? session) => session == null
      ? const PermissionService()
      : PermissionService(roles: session.roles, directPermissions: session.permissions);

  /// Creates a service from a fetched [user].
  ///
  /// For staff screens that inspect somebody else's access rather than the
  /// signed-in user's own. A `null` user yields a service that grants nothing.
  factory PermissionService.fromUser(UserModel? user) => user == null
      ? const PermissionService()
      : PermissionService(roles: user.roles, directPermissions: user.permissions);

  /// The roles assigned to the user. Each contributes its own permissions.
  final List<RoleModel> roles;

  /// Permissions granted to the user directly, on top of those from [roles].
  final List<PermissionModel> directPermissions;

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Every `resource:action` key granted: permissions inherited from [roles]
  /// plus those in [directPermissions].
  ///
  /// The set is rebuilt on every access. When checking several keys in a row,
  /// read it once into a local variable, or use [hasAnyPermission] and
  /// [hasAllPermissions], which do so internally.
  Set<String> get allPermissions => {for (final role in roles) ...role.permissions.keys, ...directPermissions.keys};

  /// Whether [action] is granted on [resource].
  ///
  /// ```dart
  /// permissions.hasPermission('order', 'refund'); // order:refund
  /// ```
  bool hasPermission(String resource, String action) => allPermissions.contains(Permissions.key(resource, action));

  /// Whether the exact `resource:action` [key] is granted.
  bool hasPermissionKey(String key) => allPermissions.contains(key);

  /// Whether **at least one** of [permissionKeys] is granted.
  ///
  /// Returns `false` for an empty iterable. This differs from
  /// `Session.canAny`, which treats an empty set as "no requirement" and
  /// returns `true`.
  bool hasAnyPermission(Iterable<String> permissionKeys) {
    final granted = allPermissions;
    return permissionKeys.any(granted.contains);
  }

  /// Whether **every one** of [permissionKeys] is granted.
  ///
  /// Returns `true` for an empty iterable.
  bool hasAllPermissions(Iterable<String> permissionKeys) {
    final granted = allPermissions;
    return permissionKeys.every(granted.contains);
  }

  /// Whether **any** action is granted on [resource].
  ///
  /// The cheap "should this section exist at all" check.
  bool canAccessResource(String resource) => allPermissions.any((key) => key.startsWith('$resource:'));

  /// The actions granted on [resource], to drive an action menu.
  ///
  /// ```dart
  /// permissions.getResourceActions('order'); // ['read', 'update']
  /// ```
  ///
  /// The order is not guaranteed. Sort the result if the UI depends on it.
  List<String> getResourceActions(String resource) => allPermissions
      .where((key) => key.startsWith('$resource:'))
      .map((key) => key.substring(resource.length + 1))
      .toList();

  // ---------------------------------------------------------------------------
  // Roles
  // ---------------------------------------------------------------------------

  /// The names of all assigned roles.
  Set<String> get roleNames => {for (final role in roles) role.name};

  /// Whether the user has the role called [roleName].
  ///
  /// Prefer permission checks for access decisions. Reserve role checks for
  /// rules that are genuinely about who someone is.
  bool hasRole(String roleName) => roleNames.contains(roleName);

  /// Whether the user has **at least one** of the roles in [names].
  bool hasAnyRole(Iterable<String> names) => names.any(roleNames.contains);

  /// Whether the user has **every** role in [names].
  bool hasAllRoles(Iterable<String> names) => names.every(roleNames.contains);

  // ---------------------------------------------------------------------------
  // CRUD shorthands
  // ---------------------------------------------------------------------------

  /// Whether the user may create a [resource].
  bool canCreate(String resource) => hasPermission(resource, Permissions.create);

  /// Whether the user may read a single [resource].
  bool canRead(String resource) => hasPermission(resource, Permissions.read);

  /// Whether the user may read **all** records of [resource], rather than only
  /// their own.
  bool canReadAll(String resource) => hasPermission(resource, Permissions.readAll);

  /// Whether the user may update a [resource].
  bool canUpdate(String resource) => hasPermission(resource, Permissions.update);

  /// Whether the user may delete a [resource].
  bool canDelete(String resource) => hasPermission(resource, Permissions.delete);
}

// -----------------------------------------------------------------------------
// Providers
// -----------------------------------------------------------------------------

/// The [PermissionService] for the signed-in session.
///
/// Follows the live session, so a role change mid-shift re-evaluates every
/// permission-aware widget on the next build. Yields a service that grants
/// nothing when no user is signed in.
final permissionServiceProvider = Provider<PermissionService>((ref) {
  final session = ref.watch(authControllerProvider.select((state) => state.sessionOrNull));
  return PermissionService.fromSession(session);
});

/// Whether the signed-in user holds one permission, keyed by [PermissionCheck].
///
/// ```dart
/// final canRefund = ref.watch(
///   hasPermissionProvider(const PermissionCheck('order', 'refund')),
/// );
/// ```
///
/// Widgets that watch this rebuild only when the answer flips, not whenever the
/// session changes.
final hasPermissionProvider = Provider.family<bool, PermissionCheck>((ref, check) {
  final service = ref.watch(permissionServiceProvider);
  return service.hasPermission(check.resource, check.action);
});

/// Whether the signed-in user may do anything with a resource name.
///
/// ```dart
/// final showReports = ref.watch(canAccessResourceProvider('report'));
/// ```
final canAccessResourceProvider = Provider.family<bool, String>((ref, resource) {
  final service = ref.watch(permissionServiceProvider);
  return service.canAccessResource(resource);
});

/// Whether the signed-in user has the role with the given name.
final hasRoleProvider = Provider.family<bool, String>((ref, roleName) {
  final service = ref.watch(permissionServiceProvider);
  return service.hasRole(roleName);
});

/// A resource and action pair, used as a value-equal key for provider
/// families.
///
/// Two checks with the same [resource] and [action] are equal, so
/// `hasPermissionProvider` reuses one provider instance for them instead of
/// creating a new one per call site.
class PermissionCheck {
  /// Creates a check for [action] on [resource].
  const PermissionCheck(this.resource, this.action);

  /// The resource name, such as `order`.
  final String resource;

  /// The action name, such as `refund`.
  final String action;

  /// The combined `resource:action` key.
  String get key => Permissions.key(resource, action);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PermissionCheck && resource == other.resource && action == other.action;

  @override
  int get hashCode => Object.hash(resource, action);

  @override
  String toString() => key;
}
