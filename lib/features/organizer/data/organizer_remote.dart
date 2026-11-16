import 'package:supabase/supabase.dart';

import '../../../core/sync/supabase_realtime_watcher.dart';

/// La copia dei dati dell'Organizzatore condivisa tra i dispositivi.
abstract interface class OrganizerRemote {
  Future<Map<String, dynamic>?> fetch();

  Future<void> save(Map<String, dynamic> data);

  /// Un evento quando un altro dispositivo salva.
  Stream<void> get changes;
}

/// Una riga per utente nella tabella `monitoraggio_personale_organizer`
/// (vedi supabase/migrations/20261112_organizer.sql).
class SupabaseOrganizerRemote implements OrganizerRemote {
  SupabaseOrganizerRemote(this._client);
  final SupabaseClient _client;
  static const table = 'monitoraggio_personale_organizer';

  String get _user {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Accesso richiesto');
    return id;
  }

  @override
  Future<Map<String, dynamic>?> fetch() async {
    final row = await _client
        .from(table)
        .select('data')
        .eq('user_id', _user)
        .maybeSingle();
    final data = row?['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  @override
  Future<void> save(Map<String, dynamic> data) => _client.from(table).upsert({
    'user_id': _user,
    'data': data,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });

  @override
  Stream<void> get changes => watchSupabaseTables(
    client: _client,
    channelName: 'desktop_organizer',
    tables: const [table],
  );
}
