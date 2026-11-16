import 'key_value_store.dart';
import 'key_value_store_stub.dart'
    if (dart.library.io) 'key_value_store_secure.dart'
    if (dart.library.js_interop) 'key_value_store_web.dart'
    as implementation;

KeyValueStore createKeyValueStore() => implementation.createKeyValueStore();
