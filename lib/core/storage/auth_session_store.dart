import 'dart:convert';

import 'package:supabase/supabase.dart';

import 'key_value_store.dart';

class AuthSessionStore implements GotrueAsyncStorage {
  AuthSessionStore(this._storage);

  static const _prefix = 'monitoraggio_personale.';
  static const _sessionKey = '${_prefix}auth.session';

  final KeyValueStore _storage;

  Future<String?> readSession() => _storage.read(_sessionKey);

  Future<void> writeSession(Session session) async {
    await _storage.write(_sessionKey, jsonEncode(session.toJson()));
  }

  Future<void> clearSession() => _storage.remove(_sessionKey);

  @override
  Future<String?> getItem({required String key}) {
    return _storage.read('$_prefix$key');
  }

  @override
  Future<void> removeItem({required String key}) {
    return _storage.remove('$_prefix$key');
  }

  @override
  Future<void> setItem({required String key, required String value}) {
    return _storage.write('$_prefix$key', value);
  }
}
