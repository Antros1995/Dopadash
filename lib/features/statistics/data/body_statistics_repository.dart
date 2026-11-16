import 'package:supabase/supabase.dart';
import '../domain/body_statistics.dart';
import '../domain/perception_statistics.dart';

abstract interface class BodyStatisticsRepository {
  Future<List<BodyDay>> loadDays();
  Future<List<PerceptionEntry>> loadPerceptions();
  Future<void> syncHistory();
  Future<void> recoverDays(
    List<DateTime> dates, {
    required bool Function() cancelled,
    required void Function(int, int) onProgress,
  });
  Future<List<BodyExperiment>> loadExperiments();
  Future<List<ExperimentLog>> loadLogs(String experimentId);
  Future<BodyExperiment> saveExperiment(BodyExperiment experiment);
  Future<void> saveLog(ExperimentLog log);
  Future<void> deleteLog(ExperimentLog log);
  Future<Map<String, dynamic>> loadPreferences();
  Future<void> savePreferences(Map<String, dynamic> preferences);
}

class SupabaseBodyStatisticsRepository implements BodyStatisticsRepository {
  SupabaseBodyStatisticsRepository(
    this.client, {
    this.historySource,
    this.daySource,
  });
  final SupabaseClient client;
  final Future<List<Map<String, dynamic>>> Function()? historySource;
  final Future<Map<String, dynamic>?> Function(DateTime)? daySource;
  String get _user =>
      client.auth.currentUser?.id ??
      (throw StateError('Sessione scaduta. Accedi nuovamente.'));

  @override
  Future<List<BodyDay>> loadDays() async {
    final user = _user;
    final days = <BodyDay>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('statistics_fitbit_days')
          .select('payload')
          .eq('user_id', user)
          .eq('source', 'fitbit')
          .order('day')
          .range(offset, offset + 499);
      days.addAll(
        rows.map((r) => BodyDay((r['payload'] as Map).cast<String, dynamic>())),
      );
      if (rows.length < 500) break;
    }
    return days;
  }

  @override
  Future<List<PerceptionEntry>> loadPerceptions() async {
    final user = _user;
    final entries = <PerceptionEntry>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('emotion_entries')
          .select('id,reference_date,emotion,intensity,energy,recorded_at')
          .eq('user_id', user)
          .order('reference_date', ascending: true)
          .order('recorded_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + 499);
      entries.addAll(rows.map(PerceptionEntry.fromJson));
      if (rows.length < 500) break;
    }
    return entries;
  }

  @override
  Future<void> syncHistory() async {
    final source = historySource;
    if (source == null) {
      throw StateError('Il backend Fitbit non è configurato.');
    }
    final user = _user;
    final raw = await source();
    if (_user != user) throw StateError('La sessione è cambiata. Riprova.');
    final unique = <String, Map<String, dynamic>>{};
    for (final d in raw) {
      if (d['source'] != null && d['source'] != 'fitbit') continue;
      final key = d['date'] as String;
      final previous = unique[key];
      if (previous == null ||
          DateTime.parse(
            d['syncedAt'],
          ).isAfter(DateTime.parse(previous['syncedAt']))) {
        unique[key] = d;
      }
    }
    final rows = unique.values
        .map(
          (d) => <String, Object?>{
            'user_id': user,
            'day': d['date'],
            'source': 'fitbit',
            'synced_at': d['syncedAt'],
            'finalized': d['finalized'] == true,
            'payload': d,
          },
        )
        .toList();
    for (var offset = 0; offset < rows.length; offset += 100) {
      await client
          .from('statistics_fitbit_days')
          .upsert(
            rows.skip(offset).take(100).toList(),
            onConflict: 'user_id,day,source',
          );
    }
  }

  @override
  Future<void> recoverDays(
    List<DateTime> dates, {
    required bool Function() cancelled,
    required void Function(int, int) onProgress,
  }) async {
    final source = daySource;
    if (source == null) {
      throw StateError('Il backend Fitbit non è configurato.');
    }
    final user = _user;
    for (var i = 0; i < dates.length; i++) {
      if (cancelled()) break;
      final day = await source(dates[i]);
      if (_user != user) throw StateError('La sessione è cambiata. Riprova.');
      if (day != null) {
        if (day['date'] != statsKey(dates[i])) {
          throw StateError(
            'Il backend ha restituito una data diversa da quella richiesta.',
          );
        }
        await client.from('statistics_fitbit_days').upsert({
          'user_id': user,
          'day': day['date'],
          'source': 'fitbit',
          'synced_at': day['syncedAt'],
          'finalized': day['finalized'] == true,
          'payload': day,
        }, onConflict: 'user_id,day,source');
      }
      onProgress(i + 1, dates.length);
    }
  }

  @override
  Future<List<BodyExperiment>> loadExperiments() async {
    final result = <BodyExperiment>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('statistics_experiments')
          .select()
          .eq('user_id', _user)
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + 499);
      result.addAll(rows.map(BodyExperiment.fromJson));
      if (rows.length < 500) break;
    }
    return result;
  }

  @override
  Future<List<ExperimentLog>> loadLogs(String experimentId) async {
    final result = <ExperimentLog>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('statistics_experiment_logs')
          .select()
          .eq('user_id', _user)
          .eq('experiment_id', experimentId)
          .order('day')
          .range(offset, offset + 499);
      result.addAll(rows.map(ExperimentLog.fromJson));
      if (rows.length < 500) break;
    }
    return result;
  }

  @override
  Future<BodyExperiment> saveExperiment(BodyExperiment experiment) async {
    experiment.validate();
    final row = {...experiment.toJson(), 'user_id': _user};
    final saved = experiment.id == null
        ? await client
              .from('statistics_experiments')
              .insert(row)
              .select()
              .single()
        : await client
              .from('statistics_experiments')
              .update(row)
              .eq('id', experiment.id!)
              .eq('user_id', _user)
              .select()
              .single();
    return BodyExperiment.fromJson(saved);
  }

  @override
  Future<void> saveLog(ExperimentLog log) async {
    await client.from('statistics_experiment_logs').upsert({
      ...log.toJson(),
      'user_id': _user,
    }, onConflict: 'user_id,experiment_id,day');
  }

  @override
  Future<void> deleteLog(ExperimentLog log) async {
    await client
        .from('statistics_experiment_logs')
        .delete()
        .eq('user_id', _user)
        .eq('experiment_id', log.experimentId)
        .eq('day', statsKey(log.date));
  }

  @override
  Future<Map<String, dynamic>> loadPreferences() async {
    final row = await client
        .from('statistics_preferences')
        .select('settings')
        .eq('user_id', _user)
        .maybeSingle();
    return (row?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  @override
  Future<void> savePreferences(Map<String, dynamic> preferences) async {
    await client.from('statistics_preferences').upsert({
      'user_id': _user,
      'settings': preferences,
    });
  }
}
