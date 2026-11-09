import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_state.dart';

/// Re-runs the router's redirect when auth changes in a way that could alter a
/// routing decision.
///
/// Assign an instance to `GoRouter.refreshListenable`. It listens to
/// `authControllerProvider` and calls [notifyListeners] only when
/// [affectsRouting] says the change matters. This keeps the router free of
/// `ref.watch`, so it is never rebuilt, while still reacting to sign-in,
/// sign-out, lock and unlock.
///
/// Notifying on every emission would re-run the whole redirect chain for
/// changes that cannot affect it and, on web, cause visible URL churn.
///
/// ## What counts as a routing change
///
/// | Change                                                | Notifies |
/// | ----------------------------------------------------- | -------- |
/// | Any change of state type (sign in, sign out, lock...) | yes      |
/// | Same signed-in user, different `userId` or `outletId` | yes      |
/// | E-mail verification flips                             | yes      |
/// | Permission keys change                                | yes      |
/// | Token refresh, re-fetched session with the same access | no       |
/// | Any other change within the same state type           | no       |
///
/// Permissions are compared as key sets, not raw lists, so a re-fetched
/// session with identical access does not re-run the redirects.
///
/// ## Lifecycle
///
/// The subscription is closed in [dispose]. A notifier that outlives the router
/// keeps the provider alive and fires into a disposed delegate, so register
/// disposal with the provider:
///
/// ```dart
/// final refresh = RouterRefreshNotifier(ref);
/// ref.onDispose(refresh.dispose);
///
/// final router = GoRouter(refreshListenable: refresh, /* ... */);
/// ```
///
/// See also:
///
/// * `RedirectPolicy`, which is what re-runs when this notifies.
class RouterRefreshNotifier extends ChangeNotifier {
  /// Starts listening to the auth state through [ref].
  ///
  /// The initial state does not notify: the router evaluates its redirect on
  /// first build anyway.
  RouterRefreshNotifier(Ref ref) {
    _subscription = ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (_affectsRouting(previous, next)) notifyListeners();
    });
  }

  late final ProviderSubscription<AuthState> _subscription;

  /// Whether moving from [previous] to [next] could change a routing decision.
  ///
  /// Returns `true` when either side is `null`, because nothing can be proven
  /// about a change from or to an unknown state.
  ///
  /// ```dart
  /// RouterRefreshNotifier.affectsRouting(
  ///   const AuthState.unknown(),
  ///   const AuthState.unauthenticated(),
  /// ); // true: the state type changed
  /// ```
  @visibleForTesting
  static bool affectsRouting(AuthState? previous, AuthState? next) => _affectsRouting(previous, next);

  static bool _affectsRouting(AuthState? previous, AuthState? next) {
    if (previous == null || next == null) return true;
    if (previous.runtimeType != next.runtimeType) return true;

    if (previous is Authenticated && next is Authenticated) {
      final a = previous.session;
      final b = next.session;
      // Permission keys, not the raw lists: a re-fetched session with the same
      // access must not re-run the redirect chain.
      return a.userId != b.userId ||
          a.outletId != b.outletId ||
          a.isEmailVerified != b.isEmailVerified ||
          !setEquals(a.permissionKeys, b.permissionKeys);
    }

    return false;
  }

  /// Stops listening to the auth state and releases this notifier.
  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
