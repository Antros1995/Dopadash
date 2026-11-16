import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_value_store.dart';

KeyValueStore createKeyValueStore() => SecureKeyValueStore();

class SecureKeyValueStore implements KeyValueStore {
  const SecureKeyValueStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> remove(String key) => _storage.delete(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}
