import 'package:supabase/supabase.dart';

import 'mfa_repository.dart';

abstract interface class AuthRepository {
  Session? get currentSession;

  Stream<AuthState> get authStateChanges;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  });

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset({required String email});

  Future<void> updatePassword({required String password});

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository, MfaRepository {
  SupabaseAuthRepository(this._client, {required Uri authRedirectUrl})
    : _authRedirectUrl = authRedirectUrl.toString();

  final SupabaseClient _client;
  final String _authRedirectUrl;

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: _authRedirectUrl,
    );
  }

  @override
  Future<void> sendPasswordReset({required String email}) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: _authRedirectUrl,
    );
  }

  @override
  Future<void> updatePassword({required String password}) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  MfaStatus get cachedMfaStatus => MfaStatus(
    pendingFactors: (_client.auth.currentUser?.factors ?? [])
        .where(
          (factor) =>
              factor.status == FactorStatus.unverified &&
              factor.factorType == FactorType.totp,
        )
        .toList(),
    factors: (_client.auth.currentUser?.factors ?? [])
        .where((factor) => factor.status == FactorStatus.verified)
        .toList(),
    isVerified:
        _client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
        AuthenticatorAssuranceLevels.aal2,
  );

  @override
  Future<MfaStatus> loadMfaStatus() async {
    // The SDK refreshes the session, including factors added on another device.
    await _client.auth.mfa.listFactors().timeout(const Duration(seconds: 30));
    return cachedMfaStatus;
  }

  @override
  Future<AuthMFAEnrollResponse> enrollAuthenticator(String name) async {
    await _readyMfaSession();
    return _client.auth.mfa
        .enroll(
          factorType: FactorType.totp,
          issuer: 'DopaDash',
          friendlyName: name,
        )
        .timeout(const Duration(seconds: 30));
  }

  @override
  Future<void> verifyAuthenticator(String factorId, String code) async {
    await _readyMfaSession();
    await _client.auth.mfa
        .challengeAndVerify(factorId: factorId, code: code)
        .timeout(const Duration(seconds: 30));
    // This SDK version does not forward mfaChallengeVerified to Realtime.
    // Existing subscriptions must immediately use the elevated aal2 token.
    await _client.realtime.setAuth(_client.auth.currentSession?.accessToken);
  }

  @override
  Future<void> removeAuthenticator(String factorId) async {
    await _client.auth.mfa
        .unenroll(factorId)
        .timeout(const Duration(seconds: 30));
  }

  @override
  Future<void> cancelAuthenticatorEnrollment(String factorId) async {
    // A verification response can time out after succeeding on the server.
    // Never turn a cancellation into removal of an already enabled factor.
    final owner = _client.auth.currentUser?.id;
    final response = await _client.auth.getUser().timeout(
      const Duration(seconds: 20),
    );
    final pending =
        response.user?.factors?.any(
          (factor) =>
              factor.id == factorId && factor.status == FactorStatus.unverified,
        ) ??
        false;
    if (pending && owner != null && owner == _client.auth.currentUser?.id) {
      await removeAuthenticator(factorId);
    }
  }

  Future<void> _readyMfaSession() async {
    final owner = _client.auth.currentUser?.id;
    final response = await _client.auth.getSession().timeout(
      const Duration(seconds: 20),
    );
    if (owner == null ||
        response?.user.id != owner ||
        _client.auth.currentUser?.id != owner) {
      throw AuthSessionMissingException();
    }
  }
}
