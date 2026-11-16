import 'package:supabase/supabase.dart';

class MfaStatus {
  const MfaStatus({
    required this.factors,
    required this.isVerified,
    this.pendingFactors = const [],
  });

  final List<Factor> factors;
  final bool isVerified;
  final List<Factor> pendingFactors;

  List<Factor> get authenticators =>
      factors.where((factor) => factor.factorType == FactorType.totp).toList();
  bool get isEnabled => factors.isNotEmpty;
  bool get needsVerification => isEnabled && !isVerified;
}

abstract interface class MfaRepository {
  MfaStatus get cachedMfaStatus;
  Future<MfaStatus> loadMfaStatus();
  Future<AuthMFAEnrollResponse> enrollAuthenticator(String name);
  Future<void> verifyAuthenticator(String factorId, String code);
  Future<void> removeAuthenticator(String factorId);
  Future<void> cancelAuthenticatorEnrollment(String factorId);
}
