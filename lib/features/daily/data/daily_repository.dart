import 'package:supabase/supabase.dart';

import '../../../core/sync/supabase_realtime_watcher.dart';
import '../../routines/domain/routine.dart' show formatDate, dateOnly, shiftDays;
import '../domain/daily_models.dart';

/// Dati della Quotidianità e dello Sport. Le tabelle sono quelle dell'app
/// per iPhone: ciò che si salva qui compare lì e viceversa.
abstract interface class DailyRepository {
  Future<DailyLifeDay> fetchDay(DateTime date);

  Future<void> addEmotion({
    required DateTime date,
    required DailyEmotion emotion,
    required int intensity,
    required DailyEnergy energy,
    int? concentration,
  });
  Future<void> deleteEmotion(String id);

  Future<void> addConcentration(ConcentrationKind kind, DateTime date, int level);
  Future<void> deleteConcentration(ConcentrationKind kind, String id);

  Future<void> saveMovement(DateTime date, int level);

  /// [usageDate] è il giorno in cui il telefono è stato usato.
  Future<void> saveScreenTime(DateTime usageDate, ScreenTime? value);

  Future<List<BodyMeasurement>> loadMeasurements();
  Future<void> saveMeasurement(BodyMeasurement measurement);
  Future<void> deleteMeasurement(DateTime date);

  /// Minuti conteggiati al cellulare per giorno di utilizzo, nel periodo.
  Future<Map<DateTime, int>> fetchScreenTimes(DateTime start, DateTime end);

  /// Movimento percepito (1–5) per giorno, nel periodo.
  Future<Map<DateTime, int>> fetchMovements(DateTime start, DateTime end);

  /// Un evento quando un altro dispositivo modifica questi dati.
  Stream<void> watchChanges();
}

class SupabaseDailyRepository implements DailyRepository {
  SupabaseDailyRepository(this._client);
  final SupabaseClient _client;

  String get _user {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Sessione scaduta. Accedi nuovamente.');
    return id;
  }

  static bool _missingColumn(PostgrestException e) =>
      e.code == '42703' || e.code == 'PGRST204';

  @override
  Stream<void> watchChanges() => watchSupabaseTables(
    client: _client,
    channelName: 'desktop_daily_life',
    tables: const [
      'emotion_entries',
      'daily_concentration_entries',
      'meditation_concentration_entries',
      'daily_movements',
      'daily_screen_times',
      'body_measurements',
    ],
  );

  @override
  Future<DailyLifeDay> fetchDay(DateTime date) async {
    final user = _user, day = formatDate(date);
    Future<List<Map<String, dynamic>>> rows(String table, String columns) =>
        _client
            .from(table)
            .select(columns)
            .eq('user_id', user)
            .eq('reference_date', day)
            .order('recorded_at', ascending: true);
    Future<List<Map<String, dynamic>>> emotions() async {
      try {
        return await rows(
          'emotion_entries',
          'id,emotion,intensity,energy,concentration,recorded_at',
        );
      } on PostgrestException catch (e) {
        if (!_missingColumn(e)) rethrow;
        return rows('emotion_entries', 'id,emotion,intensity,energy,recorded_at');
      }
    }

    final results = await Future.wait<Object?>([
      emotions(),
      rows(ConcentrationKind.day.table, 'id,concentration,recorded_at,source_key'),
      rows(
        ConcentrationKind.meditation.table,
        'id,concentration,recorded_at,source_key',
      ),
      _client
          .from('daily_movements')
          .select('level')
          .eq('user_id', user)
          .eq('reference_date', day)
          .maybeSingle(),
      _screenTime(shiftDays(date, -1), user),
    ]);
    List<T> parse<T>(Object? raw, T? Function(Map<String, dynamic>) convert) => [
      for (final row in raw as List<Map<String, dynamic>>)
        if (convert(row) case final value?) value,
    ];
    final movement = ((results[3] as Map?)?['level'] as num?)?.toInt();
    return DailyLifeDay(
      emotions: parse(results[0], EmotionEntry.fromRow),
      dayConcentration: parse(results[1], ConcentrationEntry.fromRow),
      meditationConcentration: parse(results[2], ConcentrationEntry.fromRow),
      movement: movement == null || movement < 1 ? null : movement,
      screenTime: results[4] as ScreenTime?,
    );
  }

  Future<ScreenTime?> _screenTime(DateTime date, String user) async {
    Future<Map<String, dynamic>?> read(String columns) => _client
        .from('daily_screen_times')
        .select(columns)
        .eq('user_id', user)
        .eq('reference_date', formatDate(date))
        .maybeSingle();
    Map<String, dynamic>? row;
    try {
      row = await read('minutes,excluded_activities');
    } on PostgrestException catch (e) {
      if (!_missingColumn(e)) rethrow;
      row = await read('minutes');
    }
    final minutes = (row?['minutes'] as num?)?.toInt();
    if (minutes == null) return null;
    final raw = row?['excluded_activities'];
    return ScreenTime(
      totalMinutes: minutes,
      exclusions: [
        if (raw is List)
          for (final item in raw)
            if (ScreenTimeExclusion.fromJson(item) case final value?) value,
      ],
    );
  }

  @override
  Future<void> addEmotion({
    required DateTime date,
    required DailyEmotion emotion,
    required int intensity,
    required DailyEnergy energy,
    int? concentration,
  }) => _client.from('emotion_entries').insert({
    'user_id': _user,
    'reference_date': formatDate(date),
    'emotion': emotion.key,
    'intensity': intensity.clamp(1, 5),
    'energy': energy.key,
    'concentration': ?concentration,
  });

  @override
  Future<void> deleteEmotion(String id) =>
      _client.from('emotion_entries').delete().eq('user_id', _user).eq('id', id);

  @override
  Future<void> addConcentration(
    ConcentrationKind kind,
    DateTime date,
    int level,
  ) => _client.from(kind.table).insert({
    'user_id': _user,
    'reference_date': formatDate(date),
    'concentration': level.clamp(1, 5),
  });

  @override
  Future<void> deleteConcentration(ConcentrationKind kind, String id) =>
      _client.from(kind.table).delete().eq('user_id', _user).eq('id', id);

  @override
  Future<void> saveMovement(DateTime date, int level) =>
      _client.from('daily_movements').upsert({
        'user_id': _user,
        'reference_date': formatDate(date),
        'level': level.clamp(0, 5),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,reference_date');

  @override
  Future<void> saveScreenTime(DateTime usageDate, ScreenTime? value) async {
    final user = _user, day = formatDate(usageDate);
    if (value == null) {
      await _client
          .from('daily_screen_times')
          .delete()
          .eq('user_id', user)
          .eq('reference_date', day);
      return;
    }
    final row = {
      'user_id': user,
      'reference_date': day,
      'minutes': value.totalMinutes.clamp(0, 24 * 60),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _client.from('daily_screen_times').upsert({
        ...row,
        'excluded_activities': [for (final e in value.exclusions) e.toJson()],
      }, onConflict: 'user_id,reference_date');
    } on PostgrestException catch (e) {
      if (!_missingColumn(e)) rethrow;
      await _client
          .from('daily_screen_times')
          .upsert(row, onConflict: 'user_id,reference_date');
    }
  }

  @override
  Future<Map<DateTime, int>> fetchScreenTimes(
    DateTime start,
    DateTime end,
  ) async {
    Future<List<Map<String, dynamic>>> read(String columns) => _client
        .from('daily_screen_times')
        .select(columns)
        .eq('user_id', _user)
        .gte('reference_date', formatDate(start))
        .lte('reference_date', formatDate(end))
        .order('reference_date', ascending: true);
    List<Map<String, dynamic>> rows;
    try {
      rows = await read('reference_date,minutes,excluded_activities');
    } on PostgrestException catch (e) {
      if (!_missingColumn(e)) rethrow;
      rows = await read('reference_date,minutes');
    }
    return {
      for (final row in rows)
        if (DateTime.tryParse('${row['reference_date']}') case final date?)
          dateOnly(date): ScreenTime(
            totalMinutes: (row['minutes'] as num).toInt(),
            exclusions: [
              if (row['excluded_activities'] case final List raw)
                for (final item in raw)
                  if (ScreenTimeExclusion.fromJson(item) case final value?)
                    value,
            ],
          ).countedMinutes,
    };
  }

  @override
  Future<Map<DateTime, int>> fetchMovements(DateTime start, DateTime end) async {
    final rows = await _client
        .from('daily_movements')
        .select('reference_date,level')
        .eq('user_id', _user)
        .gte('reference_date', formatDate(start))
        .lte('reference_date', formatDate(end));
    return {
      for (final row in rows)
        if (DateTime.tryParse('${row['reference_date']}') case final date?)
          if ((row['level'] as num?)?.toInt() case final level? when level > 0)
            dateOnly(date): level,
    };
  }

  @override
  Future<List<BodyMeasurement>> loadMeasurements() async {
    final rows = await _client
        .from('body_measurements')
        .select()
        .eq('user_id', _user)
        .order('reference_date', ascending: true);
    return [
      for (final row in rows)
        if (BodyMeasurement.fromRow(row) case final value?) value,
    ];
  }

  @override
  Future<void> saveMeasurement(BodyMeasurement measurement) =>
      _client.from('body_measurements').upsert({
        'user_id': _user,
        'reference_date': formatDate(measurement.date),
        for (final metric in BodyMetric.values)
          metric.column: measurement[metric],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,reference_date');

  @override
  Future<void> deleteMeasurement(DateTime date) => _client
      .from('body_measurements')
      .delete()
      .eq('user_id', _user)
      .eq('reference_date', formatDate(date));
}
