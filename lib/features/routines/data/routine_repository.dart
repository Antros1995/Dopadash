import 'package:supabase/supabase.dart';

import '../../../core/sync/supabase_realtime_watcher.dart';
import '../domain/routine.dart';

const routineCategory = 'daily_dashboard_v1';

class RoutineDayRemoteState {
  const RoutineDayRemoteState({
    required this.history,
    required this.entries,
    required this.effectiveScreenTimeMinutes,
  });

  final List<RoutineDefinition> history;
  final Map<String, RoutineEntry> entries;
  final int? effectiveScreenTimeMinutes;
}

abstract interface class RoutineRepository {
  Future<RoutineDayRemoteState> fetchDay(DateTime date);

  Future<Map<DateTime, Map<String, RoutineEntry>>> fetchEntries({
    required DateTime start,
    required DateTime endExclusive,
  });

  Future<void> saveDay({
    required DateTime date,
    required List<RoutineDefinition> history,
    required Map<String, RoutineEntry> entries,
  });
}

abstract interface class RoutineChangeFeed {
  Stream<void> watchChanges();
}

class SupabaseRoutineRepository
    implements RoutineRepository, RoutineChangeFeed {
  SupabaseRoutineRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<void> watchChanges() => watchSupabaseTables(
    client: _client,
    channelName: 'desktop_routines',
    tables: const [
      'habits',
      'habit_logs',
      'habit_log_values',
      'daily_screen_times',
    ],
  );

  @override
  Future<RoutineDayRemoteState> fetchDay(DateTime date) async {
    final userId = _requireUserId();
    final habitRows = await _client
        .from('habits')
        .select('client_key,goal_config')
        .eq('user_id', userId)
        .eq('category', routineCategory)
        .not('client_key', 'is', null)
        .order('position');

    final history = <RoutineDefinition>[];
    for (final raw in habitRows) {
      final row = Map<String, dynamic>.from(raw);
      final config = _stringMap(row['goal_config']);
      final rawHistory = config?['dashboard_history'];
      if (rawHistory is! List) continue;
      for (final rawDefinition in rawHistory) {
        final definition = _stringMap(rawDefinition);
        if (definition == null) continue;
        try {
          history.add(RoutineDefinition.fromJson(definition));
        } on Object {
          // A malformed revision must not hide the rest of the dashboard.
        }
      }
    }

    final entries = await _fetchEntriesForQuery(
      userId: userId,
      configure: (query) => query.eq('reference_date', formatDate(date)),
    );
    final screenTime = await _fetchScreenTime(
      dateOnly(date).subtract(const Duration(days: 1)),
      userId,
    );
    return RoutineDayRemoteState(
      history: List.unmodifiable(history),
      entries: Map.unmodifiable(entries[dateOnly(date)] ?? const {}),
      effectiveScreenTimeMinutes: screenTime,
    );
  }

  @override
  Future<Map<DateTime, Map<String, RoutineEntry>>> fetchEntries({
    required DateTime start,
    required DateTime endExclusive,
  }) {
    if (!dateOnly(endExclusive).isAfter(dateOnly(start))) {
      throw ArgumentError('L’intervallo delle statistiche non è valido.');
    }
    return _fetchEntriesForQuery(
      userId: _requireUserId(),
      configure: (query) => query
          .gte('reference_date', formatDate(start))
          .lt('reference_date', formatDate(endExclusive)),
    );
  }

  Future<Map<DateTime, Map<String, RoutineEntry>>> _fetchEntriesForQuery({
    required String userId,
    required dynamic Function(dynamic query) configure,
  }) async {
    dynamic query = _client
        .from('habit_logs')
        .select(
          'id,reference_date,overall_outcome,notes,habit_snapshot,updated_at,'
          'habits!inner(client_key,category)',
        )
        .eq('user_id', userId)
        .eq('habits.category', routineCategory);
    query = configure(query);
    // Il server restituisce al massimo 1000 righe per richiesta: un anno di
    // abitudini ne ha molte di più, quindi si legge a pagine fino in fondo.
    const pageSize = 1000;
    final typedRows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final rows = await query
          .order('reference_date', ascending: true)
          .order('updated_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1);
      final page = (rows as List<dynamic>).whereType<Map>().toList();
      typedRows.addAll(page.map(Map<String, dynamic>.from));
      if (page.length < pageSize) break;
    }
    final valuesByLogId = await _fetchDetailValues(userId, [
      for (final row in typedRows)
        if (row['id'] case final String id) id,
    ]);

    final result = <DateTime, Map<String, RoutineEntry>>{};
    for (final row in typedRows) {
      final habit = _stringMap(row['habits']);
      final habitId = habit?['client_key'] as String?;
      final rawDate = row['reference_date'] as String?;
      if (habitId == null || habitId.isEmpty || rawDate == null) continue;

      final snapshot = _stringMap(row['habit_snapshot']);
      final rawEntry = _stringMap(snapshot?['entry']);
      var entry = rawEntry == null
          ? const RoutineEntry()
          : RoutineEntry.fromJson(rawEntry);
      final statusName = row['overall_outcome'] as String?;
      final status = RoutineStatus.values
          .where((candidate) => candidate.name == statusName)
          .firstOrNull;
      entry = entry.copyWith(
        status: status ?? entry.status,
        notes: row['notes'] as String? ?? entry.notes,
      );
      if (entry.selectedDetailOptionId == null) {
        final logId = row['id'] as String?;
        final rawValue = logId == null
            ? null
            : valuesByLogId[logId]?.firstOrNull;
        final selectedId = rawValue?['value_text'] as String?;
        final fieldSnapshot = _stringMap(rawValue?['field_snapshot']);
        if (selectedId != null) {
          entry = entry.copyWith(
            selectedDetailOptionId: selectedId,
            selectedDetailLabelSnapshot:
                fieldSnapshot?['selectedLabel'] as String?,
            selectedDetailScoreSnapshot:
                (fieldSnapshot?['selectedScore'] as num?)?.toDouble(),
          );
        }
      }
      final date = dateOnly(DateTime.parse(rawDate));
      result.putIfAbsent(date, () => <String, RoutineEntry>{})[habitId] = entry;
    }
    return result;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchDetailValues(
    String userId,
    List<String> logIds,
  ) async {
    final result = <String, List<Map<String, dynamic>>>{};
    const batchSize = 200;
    for (var offset = 0; offset < logIds.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, logIds.length);
      final rows = await _client
          .from('habit_log_values')
          .select('log_id,value_text,field_snapshot')
          .eq('user_id', userId)
          .inFilter('log_id', logIds.sublist(offset, end));
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final logId = row['log_id'] as String?;
        if (logId != null) {
          result.putIfAbsent(logId, () => <Map<String, dynamic>>[]).add(row);
        }
      }
    }
    return result;
  }

  Future<int?> _fetchScreenTime(DateTime date, String userId) async {
    try {
      final rows = await _client
          .from('daily_screen_times')
          .select('minutes,excluded_activities')
          .eq('user_id', userId)
          .eq('reference_date', formatDate(date))
          .limit(1);
      if (rows.isEmpty) return null;
      final total = (rows.first['minutes'] as num).toInt();
      final rawExclusions = rows.first['excluded_activities'];
      var excluded = 0;
      if (rawExclusions is List) {
        for (final raw in rawExclusions) {
          if (raw is Map) {
            final minutes = (raw['minutes'] as num?)?.toInt();
            if (minutes != null && minutes > 0) excluded += minutes;
          }
        }
      }
      return (total - excluded).clamp(0, 24 * 60).toInt();
    } on PostgrestException catch (error) {
      if (error.code != '42703' && error.code != 'PGRST204') rethrow;
      final rows = await _client
          .from('daily_screen_times')
          .select('minutes')
          .eq('user_id', userId)
          .eq('reference_date', formatDate(date))
          .limit(1);
      return rows.isEmpty ? null : (rows.first['minutes'] as num).toInt();
    }
  }

  @override
  Future<void> saveDay({
    required DateTime date,
    required List<RoutineDefinition> history,
    required Map<String, RoutineEntry> entries,
  }) async {
    _requireUserId();
    await _client.rpc(
      'save_daily_dashboard_day',
      params: <String, dynamic>{
        'p_reference_date': formatDate(date),
        'p_habit_history': [
          for (final definition in history) definition.toJson(),
        ],
        'p_entries': [
          for (final entry in entries.entries)
            <String, dynamic>{'habitId': entry.key, ...entry.value.toJson()},
        ],
      },
    );
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sessione scaduta. Accedi nuovamente.');
    }
    return userId;
  }
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}
