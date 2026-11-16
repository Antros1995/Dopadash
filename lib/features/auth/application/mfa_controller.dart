import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../data/mfa_repository.dart';

class MfaController extends ChangeNotifier {
  MfaController(this._repository);

  final MfaRepository _repository;
  MfaStatus? _status;
  String? _userId;
  Object? _error;
  int _revision = 0;
  bool _checked = false;
  bool _disposed = false;
  Future<void>? _loading;

  MfaStatus? get status => _status;
  String? get userId => _userId;
  bool get isChecking => _userId != null && !_checked && _error == null;
  bool get hasError => _error != null;
  bool get needsVerification => _status?.needsVerification ?? false;
  bool get canEnter => _checked && !hasError && !needsVerification;

  void bindSession(Session? session, {bool recheck = false}) {
    final userId = session?.user.id;
    if (userId != _userId || recheck) {
      _revision++;
      _userId = userId;
      _checked = false;
      _error = null;
      _loading = null;
      _status = userId == null ? null : _repository.cachedMfaStatus;
      if (userId != null) unawaited(refresh());
      _notify();
    } else if (userId != null) {
      _status = _repository.cachedMfaStatus;
      _notify();
    }
  }

  Future<void> refresh() {
    if (_userId == null) return Future.value();
    if (_loading case final loading?) return loading;
    final revision = _revision;
    _error = null;
    _notify();
    final operation = _refresh(revision);
    _loading = operation;
    return operation;
  }

  Future<void> _refresh(int revision) async {
    try {
      final status = await _repository.loadMfaStatus();
      if (revision != _revision || _disposed) return;
      _status = status;
      _checked = true;
    } on Object catch (error) {
      if (revision != _revision || _disposed) return;
      _error = error;
    } finally {
      if (revision == _revision && !_disposed) {
        _loading = null;
        _notify();
      }
    }
  }

  Future<AuthMFAEnrollResponse> enroll(String name) {
    if (!canEnter) throw const AuthException('MFA verification required');
    return _repository.enrollAuthenticator(name.trim());
  }

  Future<void> verify(String factorId, String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const AuthException('Invalid MFA code');
    }
    final revision = _revision;
    await _repository.verifyAuthenticator(factorId, code);
    if (revision != _revision || _disposed) return;
    _status = _repository.cachedMfaStatus;
    _checked = true;
    _error = null;
    _notify();
  }

  Future<void> cancelEnrollment(String factorId) =>
      _repository.cancelAuthenticatorEnrollment(factorId);

  Future<void> remove({
    required String factorId,
    required String confirmationFactorId,
    required String code,
  }) async {
    // Require a fresh code, even if this session already has assurance aal2.
    final revision = _revision;
    await verify(confirmationFactorId, code);
    if (revision != _revision || _disposed) {
      throw AuthSessionMissingException();
    }
    await _repository.removeAuthenticator(factorId);
    await refresh();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
