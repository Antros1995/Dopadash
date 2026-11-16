import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../data/auth_repository.dart';
import '../data/mfa_repository.dart';
import 'mfa_controller.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    bool initialPasswordRecovery = false,
  }) : _repository = repository,
       _session = repository.currentSession,
       _isPasswordRecovery = initialPasswordRecovery {
    if (repository is MfaRepository) {
      mfa = MfaController(repository as MfaRepository);
      mfa!.addListener(notifyListeners);
      mfa!.bindSession(_session);
    }
    _subscription = repository.authStateChanges.listen(
      _onAuthStateChanged,
      onError: (Object error, StackTrace stack) {
        // A temporary refresh/network failure is not a sign-out. The SDK retries
        // and emits signedOut itself if the refresh token is no longer valid.
      },
    );
  }

  final AuthRepository _repository;
  MfaController? mfa;
  late final StreamSubscription<AuthState> _subscription;
  Session? _session;
  bool _isPasswordRecovery;

  Session? get session => _session;
  bool get isAuthenticated => _session != null;
  bool get isPasswordRecovery => _isPasswordRecovery;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => _repository.signIn(email: email, password: password);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) => _repository.signUp(email: email, password: password);

  Future<void> sendPasswordReset(String email) {
    return _repository.sendPasswordReset(email: email);
  }

  Future<void> updatePassword(String password) async {
    if (mfa case final security? when !security.canEnter) {
      throw const AuthException('MFA verification required');
    }
    await _repository.updatePassword(password: password);
    _isPasswordRecovery = false;
    notifyListeners();
  }

  Future<void> signOut() => _repository.signOut();

  void _onAuthStateChanged(AuthState state) {
    _session = state.session;
    mfa?.bindSession(
      state.session,
      recheck:
          state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.passwordRecovery,
    );
    if (state.event == AuthChangeEvent.passwordRecovery) {
      _isPasswordRecovery = true;
    } else if (state.event == AuthChangeEvent.signedOut) {
      _isPasswordRecovery = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    mfa?.removeListener(notifyListeners);
    mfa?.dispose();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
