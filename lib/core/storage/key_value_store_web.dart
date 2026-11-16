import 'package:web/web.dart' as web;

import 'key_value_store.dart';

KeyValueStore createKeyValueStore() => WebKeyValueStore();

class WebKeyValueStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async =>
      web.window.localStorage.getItem(key);

  @override
  Future<void> remove(String key) async =>
      web.window.localStorage.removeItem(key);

  @override
  Future<void> write(String key, String value) async {
    web.window.localStorage.setItem(key, value);
  }
}
