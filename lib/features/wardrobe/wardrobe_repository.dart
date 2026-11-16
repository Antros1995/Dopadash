import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import '../../core/sync/supabase_realtime_watcher.dart';

/// Gli strati di un outfit, dalla testa ai piedi: d'inverno ci si veste a
/// pezzi (maglia, giubbino, cappello…). Ogni strato può avere più capi.
/// Le chiavi sono salvate nel database: `top`, `bottom` e `shoes` esistevano
/// già e non vanno cambiate.
enum OutfitSlot {
  head('head', 'Cappello', '🧢', 'Cappello, berretto, fascia'),
  outer('outer', 'Giubbino', '🧥', 'Giubbino, cappotto, giacca, gilet'),
  top(
    'top',
    'Maglie e camicie',
    '👕',
    'Maglia, camicia, felpa, t-shirt: anche due insieme',
  ),
  bottom('bottom', 'Pantaloni', '👖', 'Pantaloni, jeans, gonna, shorts'),
  shoes('shoes', 'Scarpe', '👟', 'Scarpe, stivali, sneakers'),
  accessory(
    'accessory',
    'Accessori',
    '🧣',
    'Sciarpa, guanti, cintura, borsa, occhiali',
  );

  const OutfitSlot(this.key, this.label, this.emoji, this.hint);
  final String key, label, emoji, hint;
  static OutfitSlot? parse(Object? value) =>
      values.where((s) => s.key == value).firstOrNull;
}

const outfitSeasons = ['Estate', 'Mezza stagione', 'Inverno'];
const outfitStyles = ['Elegante', 'Lavoro', 'Casual', 'Sportivo'];

const outfitTagEmoji = <String, String>{
  'Estate': '☀️',
  'Mezza stagione': '🍂',
  'Inverno': '❄️',
  'Elegante': '🎩',
  'Lavoro': '💼',
  'Casual': '😎',
  'Sportivo': '🏃',
};

/// Un capo dell'armadio: una foto già caricata, che si può usare in più
/// outfit senza caricarla di nuovo.
class Garment {
  const Garment({
    required this.path,
    required this.slot,
    this.url,
    this.bytes,
    this.outfits = const [],
  });
  final String path;
  final OutfitSlot slot;
  final String? url;
  final Uint8List? bytes;

  /// Gli outfit che lo usano.
  final List<Outfit> outfits;

  OutfitPiece piece(OutfitSlot slot) =>
      OutfitPiece(slot: slot, path: path, url: url, bytes: bytes);

  /// Tutti i capi distinti degli outfit, con lo strato in cui sono usati
  /// più spesso.
  static List<Garment> collect(List<Outfit> outfits) {
    final uses = <String, List<(Outfit, OutfitPiece)>>{};
    for (final outfit in outfits) {
      for (final piece in outfit.pieces) {
        if (piece.path case final path?) {
          (uses[path] ??= []).add((outfit, piece));
        }
      }
    }
    return [
      for (final entry in uses.entries)
        Garment(
          path: entry.key,
          url: entry.value.map((u) => u.$2.url).nonNulls.firstOrNull,
          bytes: entry.value.map((u) => u.$2.bytes).nonNulls.firstOrNull,
          slot: _mostUsed(entry.value.map((u) => u.$2.slot)),
          outfits: {for (final u in entry.value) u.$1}.toList(),
        ),
    ];
  }

  static OutfitSlot _mostUsed(Iterable<OutfitSlot> slots) {
    final counts = <OutfitSlot, int>{};
    for (final s in slots) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}

class OutfitPiece {
  const OutfitPiece({required this.slot, this.path, this.url, this.bytes});
  final OutfitSlot slot;

  /// Percorso nell'archivio; nullo finché la foto non è stata caricata.
  final String? path;

  /// Indirizzo temporaneo per mostrarla.
  final String? url;

  /// Foto appena scelta, ancora da caricare.
  final Uint8List? bytes;
}

class Outfit {
  const Outfit({
    required this.id,
    this.name = '',
    this.seasons = const {},
    this.styles = const {},
    this.pieces = const [],
    this.createdAt,
  });
  final String id, name;
  final Set<String> seasons, styles;
  final List<OutfitPiece> pieces;
  final DateTime? createdAt;

  Iterable<OutfitPiece> of(OutfitSlot slot) =>
      pieces.where((p) => p.slot == slot);
}

/// Outfit dell'utente: una riga per outfit nella tabella
/// `monitoraggio_personale_outfits` e le foto nell'archivio privato
/// `outfit-photos` (vedi supabase/migrations/20261114_outfits.sql).
class WardrobeRepository {
  WardrobeRepository(this._client);
  final SupabaseClient _client;
  static const table = 'monitoraggio_personale_outfits';
  static const bucket = 'outfit-photos';

  String get _user {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Sessione scaduta. Accedi nuovamente.');
    return id;
  }

  Stream<void> watchChanges() => watchSupabaseTables(
    client: _client,
    channelName: 'desktop_outfits',
    tables: const [table],
  );

  Future<List<Outfit>> load() async {
    final rows = await _client
        .from(table)
        .select()
        .eq('user_id', _user)
        .order('created_at', ascending: false);
    final paths = <String>{
      for (final row in rows)
        for (final piece in (row['pieces'] as List? ?? const []))
          if (piece is Map && piece['path'] is String) piece['path'] as String,
    }.toList();
    final urls = <String, String>{};
    if (paths.isNotEmpty) {
      final signed = await _client.storage
          .from(bucket)
          .createSignedUrls(paths, 3600);
      for (final s in signed) {
        if (s.signedUrl.isNotEmpty) urls[s.path] = s.signedUrl;
      }
    }
    Set<String> strings(Object? value) => {
      if (value is List)
        for (final v in value)
          if (v is String && v.isNotEmpty) v,
    };
    return [
      for (final row in rows)
        Outfit(
          id: row['id'] as String,
          name: row['name'] as String? ?? '',
          seasons: strings(row['seasons']),
          styles: strings(row['styles']),
          createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
          pieces: [
            for (final piece in (row['pieces'] as List? ?? const []))
              if (piece is Map)
                if (OutfitSlot.parse(piece['slot']) case final slot?)
                  if (piece['path'] case final String path)
                    OutfitPiece(slot: slot, path: path, url: urls[path]),
          ],
        ),
    ];
  }

  /// Salva un outfit: carica le foto nuove, poi scrive la riga. Le foto tolte
  /// rispetto a [previous] vengono cancellate dall'archivio.
  Future<void> save(Outfit outfit, {Outfit? previous}) async {
    final user = _user;
    final pieces = <Map<String, String>>[];
    final uploaded = <String>[];
    try {
      for (final piece in outfit.pieces) {
        var path = piece.path;
        if (path == null && piece.bytes != null) {
          path =
              '$user/${outfit.id}/${piece.slot.key}_${DateTime.now().microsecondsSinceEpoch}.jpg';
          await _client.storage
              .from(bucket)
              .uploadBinary(
                path,
                piece.bytes!,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          uploaded.add(path);
        }
        if (path != null) pieces.add({'slot': piece.slot.key, 'path': path});
      }
      await _client.from(table).upsert({
        'id': outfit.id,
        'user_id': user,
        'name': outfit.name.trim(),
        'seasons': outfit.seasons.toList(),
        'styles': outfit.styles.toList(),
        'pieces': pieces,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Niente foto orfane se il salvataggio non riesce.
      if (uploaded.isNotEmpty) {
        await _client.storage.from(bucket).remove(uploaded).catchError((_) {
          return <FileObject>[];
        });
      }
      rethrow;
    }
    await _removeUnused([
      for (final p in previous?.pieces ?? const <OutfitPiece>[])
        if (p.path != null) p.path!,
    ]);
  }

  Future<void> delete(Outfit outfit) async {
    await _client.from(table).delete().eq('user_id', _user).eq('id', outfit.id);
    await _removeUnused([
      for (final p in outfit.pieces)
        if (p.path != null) p.path!,
    ]);
  }

  /// Cancella dall'archivio solo le foto che nessun outfit usa più: lo stesso
  /// capo può stare in più outfit.
  Future<void> _removeUnused(List<String> candidates) async {
    if (candidates.isEmpty) return;
    final rows = await _client
        .from(table)
        .select('pieces')
        .eq('user_id', _user);
    final used = <String>{
      for (final row in rows)
        for (final piece in (row['pieces'] as List? ?? const []))
          if (piece is Map && piece['path'] is String) piece['path'] as String,
    };
    final unused = candidates.where((p) => !used.contains(p)).toList();
    if (unused.isNotEmpty) await _client.storage.from(bucket).remove(unused);
  }
}

/// Foto dei progressi fisici: sono quelle dell'app per iPhone (tabella
/// `progress_photos`, archivio privato `progress-photos`).
class ProgressPhoto {
  const ProgressPhoto({
    required this.id,
    required this.date,
    required this.path,
    required this.url,
  });
  final String id, path, url;
  final DateTime date;
}

class ProgressPhotoRepository {
  ProgressPhotoRepository(this._client);
  final SupabaseClient _client;
  static const bucket = 'progress-photos';

  String get _user {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Sessione scaduta. Accedi nuovamente.');
    return id;
  }

  Future<List<ProgressPhoto>> load() async {
    final rows = await _client
        .from('progress_photos')
        .select()
        .eq('user_id', _user)
        .order('photo_date', ascending: true)
        .order('created_at', ascending: true);
    final paths = [
      for (final row in rows)
        if (row['storage_path'] case final String path) path,
    ];
    final urls = <String, String>{};
    if (paths.isNotEmpty) {
      final signed = await _client.storage
          .from(bucket)
          .createSignedUrls(paths, 3600);
      for (final s in signed) {
        if (s.signedUrl.isNotEmpty) urls[s.path] = s.signedUrl;
      }
    }
    return [
      for (final row in rows)
        if (DateTime.tryParse('${row['photo_date']}') case final date?)
          if (urls[row['storage_path']] case final url?)
            ProgressPhoto(
              id: row['id'] as String,
              date: DateTime(date.year, date.month, date.day),
              path: row['storage_path'] as String,
              url: url,
            ),
    ];
  }

  Future<void> add(DateTime date, Uint8List bytes) async {
    final user = _user;
    final path = '$user/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    try {
      await _client.from('progress_photos').insert({
        'user_id': user,
        'photo_date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'storage_path': path,
      });
    } catch (_) {
      await _client.storage.from(bucket).remove([path]);
      rethrow;
    }
  }

  Future<void> delete(ProgressPhoto photo) async {
    await _client
        .from('progress_photos')
        .delete()
        .eq('user_id', _user)
        .eq('id', photo.id);
    await _client.storage.from(bucket).remove([photo.path]);
  }
}
