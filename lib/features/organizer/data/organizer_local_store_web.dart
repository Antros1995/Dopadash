import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'organizer_local_store.dart';

OrganizerLocalStore createOrganizerLocalStore() => WebOrganizerLocalStore();

class WebOrganizerLocalStore implements OrganizerLocalStore {
  WebOrganizerLocalStore() {
    // La pagina incorporata scrive nella stessa memoria: il browser avvisa
    // questa finestra a ogni suo salvataggio.
    _listener = ((web.Event event) {
      if ((event as web.StorageEvent).key == key && !_changes.isClosed) {
        _changes.add(null);
      }
    }).toJS;
    web.window.addEventListener('storage', _listener);
  }

  static const key = 'organizzatore.v3';
  final _changes = StreamController<void>.broadcast();
  late final JSFunction _listener;

  @override
  String? read() => web.window.localStorage.getItem(key);

  @override
  void write(String json) => web.window.localStorage.setItem(key, json);

  @override
  void backup(String json) {
    try {
      web.window.localStorage.setItem('$key.backup', json);
    } catch (_) {
      // Memoria piena: la copia di riserva è facoltativa.
    }
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  void dispose() {
    web.window.removeEventListener('storage', _listener);
    unawaited(_changes.close());
  }
}
