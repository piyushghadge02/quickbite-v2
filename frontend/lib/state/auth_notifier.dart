/// Sign-in state machine.
///
/// States:
/// * [AuthPhase.signedOut] — initial; also the target of sign-out / 401.
/// * [AuthPhase.restoring] — brief splash while a saved mobile token is
///   validated with `GET /api/v1/me`.
/// * [AuthPhase.signingIn] — loading; the sign-in button shows a spinner and
///   is disabled so the user cannot double-submit.
/// * [AuthPhase.error] — [AuthFailure.invalidCredentials] (401) or
///   [AuthFailure.network] (timeout/unreachable) or [AuthFailure.unknown].
///   The sign-in screen renders a distinct banner per kind.
/// * [AuthPhase.signedIn] — [user] is non-null.
///
/// Token handling: the bearer token lives in the in-memory [ApiClient] for
/// the session. It is additionally persisted through [TokenStorage] —
/// memory-only on web, `flutter_secure_storage` on mobile.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import '../storage/token_storage.dart';
import 'providers.dart';

enum AuthPhase { signedOut, restoring, signingIn, error, signedIn }

enum AuthFailure { invalidCredentials, network, unknown }

class AuthState {
  final AuthPhase phase;
  final User? user;
  final AuthFailure? failure;
  final String? failureMessage;

  const AuthState({
    required this.phase,
    this.user,
    this.failure,
    this.failureMessage,
  });

  const AuthState.signedOut() : this(phase: AuthPhase.signedOut);

  bool get isSignedIn => phase == AuthPhase.signedIn && user != null;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Defer the restore so `build` stays synchronous.
    Future.microtask(_restoreSession);
    return const AuthState(phase: AuthPhase.restoring);
  }

  ApiClient get _api => ref.read(apiClientProvider);
  TokenStorage get _tokens => ref.read(tokenStorageProvider);

  Future<void> _restoreSession() async {
    final token = await _tokens.read();
    if (token == null || token.isEmpty) {
      state = const AuthState.signedOut();
      return;
    }
    _api.setAuthToken(token);
    try {
      final user = await _api.me();
      state = AuthState(phase: AuthPhase.signedIn, user: user);
    } catch (_) {
      // Saved token is dead — drop it and show the sign-in screen.
      await _tokens.delete();
      _api.setAuthToken(null);
      state = const AuthState.signedOut();
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = const AuthState(phase: AuthPhase.signingIn);
    try {
      final resp = await _api.login(email: email, password: password);
      _api.setAuthToken(resp.accessToken);
      await _tokens.save(resp.accessToken);
      state = AuthState(phase: AuthPhase.signedIn, user: resp.user);
    } on UnauthorizedException {
      state = const AuthState(
        phase: AuthPhase.error,
        failure: AuthFailure.invalidCredentials,
        failureMessage: 'Incorrect email or password. Please try again.',
      );
    } on NetworkException catch (e) {
      state = AuthState(
        phase: AuthPhase.error,
        failure: AuthFailure.network,
        failureMessage: e.message,
      );
    } on ApiException catch (e) {
      state = AuthState(
        phase: AuthPhase.error,
        failure: AuthFailure.unknown,
        failureMessage: e.message,
      );
    }
  }

  /// The ApiClient calls this on any HTTP 401 (expired/revoked token).
  Future<void> handleUnauthorized() async {
    await _tokens.delete();
    _api.setAuthToken(null);
    state = const AuthState(
      phase: AuthPhase.error,
      failure: AuthFailure.unknown,
      failureMessage: 'Your session expired. Please sign in again.',
    );
  }

  Future<void> signOut() async {
    await _tokens.delete();
    _api.setAuthToken(null);
    state = const AuthState.signedOut();
  }

  void clearError() {
    if (state.phase == AuthPhase.error) {
      state = const AuthState.signedOut();
    }
  }
}
