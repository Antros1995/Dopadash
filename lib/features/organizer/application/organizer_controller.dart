import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/organizer_local_store.dart';
import '../data/organizer_remote.dart';
import '../domain/organizer_summary.dart';

/// Tiene aggiornato il riepilogo dell'Organizzatore mostrato nella Home e,
/// quando c'è un account, allinea la copia di questo dispositivo con quella
/// condivisa: vince la copia salvata più di recente (campo `savedAt`).
class OrganizerController extends ChangeNotifier {
  OrganizerController({
    required OrganizerLocalStore store,
    OrganizerRemote? remote,
    DateTime Function()? now,
    this.pushDelay = const Duration(milliseconds: 1500),
  }) : _store = store,
       _remote = remote,
       _now = now ?? DateTime.now;

  final OrganizerLocalStore _store;
  final OrganizerRemote? _remote;
  final DateTime Function() _now;
  final Duration pushDelay;

  OrganizerSummary summary = const OrganizerSummary();

  /// Falso finché la copia condivisa non è raggiungibile (per esempio prima
  /// di aver creato la tabella): i dati restano solo su questo dispositivo.
  bool get synced => _remote != null && _synced;
  bool get hasRemote => _remote != null;
  bool _synced = false, _busy = false, _again = false, _disposed = false;
  Timer? _pushTimer;
  StreamSubscription<void>? _local, _shared;

  void start() {
    _refresh();
    _local = _store.changes.listen((_) {
      _refresh();
      _pushTimer?.cancel();
      _pushTimer = Timer(pushDelay, () => unawaited(synchronize()));
    });
    if (_remote == null) return;
    // Il canale emette anche appena connesso: è la prima lettura.
    _shared = _remote.changes.listen((_) => unawaited(synchronize()));
  }

  /// Confronta le due copie e porta la più recente dall'altra parte.
  Future<void> synchronize() async {
    final remote = _remote;
    if (remote == null || _disposed) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _reconcile(remote);
      } while (_again && !_disposed);
      _setSynced(true);
    } catch (_) {
      _setSynced(false);
    } finally {
      _busy = false;
    }
  }

  Future<void> _reconcile(OrganizerRemote remote) async {
    final shared = await remote.fetch();
    if (_disposed) return;
    final raw = _store.read();
    final local = _decode(raw);
    final localHas = _hasContent(local);
    final localAt = _stamp(local), sharedAt = _stamp(shared);
    if (shared == null || !_hasContent(shared)) {
      if (localHas) await _push(remote, local!);
      return;
    }
    final sharedIsNewer =
        sharedAt != null && (localAt == null || sharedAt.isAfter(localAt));
    if (!localHas || sharedIsNewer) {
      // Mai perdere appunti locali non ancora sincronizzati.
      if (localHas && localAt == null && raw != null) _store.backup(raw);
      _store.write(jsonEncode(shared));
      _refresh();
    } else if (localAt == null ||
        sharedAt == null ||
        localAt.isAfter(sharedAt)) {
      await _push(remote, local!);
    }
  }

  Future<void> _push(OrganizerRemote remote, Map<String, dynamic> data) async {
    if (_stamp(data) == null) {
      data['savedAt'] = _now().toUtc().toIso8601String();
      _store.write(jsonEncode(data));
    }
    await remote.save(data);
  }

  void _refresh() {
    summary = OrganizerSummary.fromJson(_store.read(), _now());
    if (!_disposed) notifyListeners();
  }

  void _setSynced(bool value) {
    if (_synced == value || _disposed) return;
    _synced = value;
    notifyListeners();
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  static DateTime? _stamp(Map<String, dynamic>? data) =>
      DateTime.tryParse('${data?['savedAt'] ?? ''}');

  static final _tags = RegExp(r'<[^>]*>|&nbsp;|\s');

  /// Vero se c'è almeno un progetto oltre all'Inbox o del testo in un foglio.
  static bool _hasContent(Map<String, dynamic>? data) {
    final projects = data?['projects'];
    if (projects is! List) return false;
    if (projects.length > 1) return true;
    for (final project in projects) {
      final sheets = project is Map ? project['sheets'] : null;
      if (sheets is! List) continue;
      for (final sheet in sheets) {
        if (sheet is Map &&
            '${sheet['html'] ?? ''}'.replaceAll(_tags, '').isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _pushTimer?.cancel();
    unawaited(_local?.cancel());
    unawaited(_shared?.cancel());
    _store.dispose();
    super.dispose();
  }
}
