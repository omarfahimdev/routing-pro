import 'package:freezed_annotation/freezed_annotation.dart';

import 'session.dart';

part 'auth_state.freezed.dart';

/// ================================================================================
/// Four states, and the router handles all four exhaustively.
///
/// [Unknown] is not "loading" — it is "we have not yet restored the session
/// from disk". Without it, a web refresh flashes the login screen before the
/// token is read back, which looks broken to anyone standing at a till.
/// ================================================================================

@freezed
sealed class AuthState with _$AuthState {
  const AuthState._();

  /// ================================================================================
  /// The initial loading phase when the app boots up and is checking local storage
  /// or secure vaults for existing tokens.
  ///
  ///
  /// on build() -> authController
  /// Silently call() restore user and
  /// state => AuthState.unknown();
  /// ================================================================================
  const factory AuthState.unknown() = AuthUnknown;

  /// ================================================================================
  /// NO ACTIVE USER.
  ///
  /// on session = null, sessionTokenExpired, signOut.
  /// ================================================================================
  const factory AuthState.unauthenticated({String? reason}) = Unauthenticated;

  /// ================================================================================
  /// IDLE TIMEOUT, LIKE LOCK SCREEN.
  ///
  /// keeps the session, gates the UI.
  /// ================================================================================
  const factory AuthState.locked({required Session session}) = SessionLocked;

  /// ================================================================================
  /// USER FULLY LOGGED IN.
  ///
  /// unlocked, and actively operating the system.
  /// ================================================================================
  const factory AuthState.authenticated({required Session session}) = Authenticated;

  Session? get sessionOrNull => switch (this) {
    Authenticated(:final session) => session,
    SessionLocked(:final session) => session,
    _ => null,
  };

  bool get isAuthenticated => this is Authenticated;
  bool get isBootstrapping => this is AuthUnknown;
  bool get isLocked => this is SessionLocked;
}
