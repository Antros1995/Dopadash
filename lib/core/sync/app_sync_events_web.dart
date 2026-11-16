import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Stream<void> appSyncEvents() {
  late final StreamController<void> events;
  final listener = ((web.Event event) {
    if (web.document.visibilityState == 'visible' && !events.isClosed) {
      events.add(null);
    }
  }).toJS;
  events = StreamController<void>(
    onListen: () {
      web.window.addEventListener('online', listener);
      web.window.addEventListener('focus', listener);
      web.document.addEventListener('visibilitychange', listener);
    },
    onCancel: () {
      web.window.removeEventListener('online', listener);
      web.window.removeEventListener('focus', listener);
      web.document.removeEventListener('visibilitychange', listener);
    },
  );
  return events.stream;
}
