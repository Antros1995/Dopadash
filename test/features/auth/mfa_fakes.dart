import 'dart:async';
import 'dart:convert';

import 'package:monitoraggio_personale_desktop/features/auth/data/auth_repository.dart';
import 'package:monitoraggio_personale_desktop/features/auth/data/mfa_repository.dart';
import 'package:supabase/supabase.dart';

Factor factor(
  String id, {
  FactorStatus status = FactorStatus.verified,
  FactorType type = FactorType.totp,
}) => Factor(
  id: id,
  friendlyName: id,
  factorType: type,
  status: status,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Session session({String id = 'owner', String aal = 'aal1'}) => Session(
  accessToken:
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': id, 'aal': aal}))).replaceAll('=', '')}.signature',
  refreshToken: 'test-refresh',
  tokenType: 'bearer',
  expiresIn: 3600,
  user: User(
    id: id,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

class FakeMfaRepository implements AuthRepository, MfaRepository {
  FakeMfaRepository({MfaStatus? status, Session? initialSession})
    : value = status ?? const MfaStatus(factors: [], isVerified: false),
      currentSession = initialSession ?? session();
  final changes = StreamController<AuthState>.broadcast(sync: true);
  MfaStatus value;
  int loads = 0;
  int enrollments = 0;
  int passwordUpdates = 0;
  final removed = <String>[];
  final cancelled = <String>[];
  final verified = <String>[];
  Object? loadError;
  Completer<MfaStatus>? loading;
  Completer<void>? verifying;

  @override
  Session? currentSession;
  @override
  Stream<AuthState> get authStateChanges => changes.stream;
  @override
  MfaStatus get cachedMfaStatus => value;
  @override
  Future<MfaStatus> loadMfaStatus() async {
    loads++;
    if (loadError case final error?) throw error;
    return loading?.future ?? value;
  }

  @override
  Future<AuthMFAEnrollResponse> enrollAuthenticator(String name) async {
    enrollments++;
    return const AuthMFAEnrollResponse(
      id: 'pending',
      type: FactorType.totp,
      totp: TOTPEnrollment(
        qrCode: '',
        secret: 'TESTONLYSECRET',
        uri: 'otpauth://totp/Test?secret=TESTONLYSECRET&issuer=Test',
      ),
    );
  }

  @override
  Future<void> verifyAuthenticator(String factorId, String code) async {
    if (code != '123456') {
      throw const AuthException(
        'Incorrect TOTP',
        code: 'mfa_verification_failed',
      );
    }
    if (verifying case final pending?) await pending.future;
    verified.add(factorId);
    value = MfaStatus(
      factors: [...value.factors, if (factorId == 'pending') factor('pending')],
      isVerified: true,
    );
  }

  @override
  Future<void> removeAuthenticator(String factorId) async {
    removed.add(factorId);
    value = MfaStatus(
      factors: value.factors.where((f) => f.id != factorId).toList(),
      isVerified: true,
    );
  }

  @override
  Future<void> cancelAuthenticatorEnrollment(String factorId) async {
    cancelled.add(factorId);
  }

  void emit(AuthChangeEvent event, Session? newSession) {
    currentSession = newSession;
    changes.add(AuthState(event, newSession));
  }

  @override
  Future<void> signOut() async => emit(AuthChangeEvent.signedOut, null);
  @override
  Future<void> updatePassword({required String password}) async {
    passwordUpdates++;
  }

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async => AuthResponse(session: currentSession);
  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async => AuthResponse(session: currentSession);
  @override
  Future<void> sendPasswordReset({required String email}) async {}
}
