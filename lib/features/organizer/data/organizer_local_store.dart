import 'dart:async';

export 'organizer_local_store_stub.dart'
    if (dart.library.js_interop) 'organizer_local_store_web.dart';

/// La copia dei dati dell'Organizzatore su questo dispositivo: è la stessa
/// memoria del browser che usa la pagina incorporata.
abstract interface class OrganizerLocalStore {
  String? read();

  void write(String json);

  /// Tiene da parte una copia prima che venga sostituita da quella remota.
  void backup(String json);

  /// Un evento ogni volta che la pagina dell'Organizzatore salva.
  Stream<void> get changes;

  void dispose();
}

/// Memoria volatile: usata fuori dal browser e nei test.
class MemoryOrganizerLocalStore implements OrganizerLocalStore {
  MemoryOrganizerLocalStore([this.value]);
  String? value, saved;
  final _changes = StreamController<void>.broadcast();

  /// Simula un salvataggio fatto dalla pagina dell'Organizzatore.
  void edit(String json) {
    value = json;
    _changes.add(null);
  }

  @override
  String? read() => value;
  @override
  void write(String json) => value = json;
  @override
  void backup(String json) => saved = json;
  @override
  Stream<void> get changes => _changes.stream;
  @override
  void dispose() => unawaited(_changes.close());
}
