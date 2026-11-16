import 'package:supabase/supabase.dart';

import '../../daily/data/daily_repository.dart';
import '../../daily/domain/daily_models.dart';
import '../../data_export/data/diet_export.dart';
import '../../routines/data/routine_repository.dart';
import '../../routines/domain/routine.dart';

/// Parametri non Fitbit da mettere a confronto in Statistiche → Panoramica.
/// Ogni serie è un valore per giorno, con la data `AAAA-MM-GG` come chiave.
enum CompareSource {
  meditation,
  dayConcentration,
  meditationConcentration,
  energy,
  mood,
  screen,
  movement,
  calories,
}

class CompareSources {
  CompareSources({
    required this.client,
    required this.daily,
    required this.routines,
    required this.diet,
  });

  final SupabaseClient client;
  final DailyRepository daily;
  final RoutineRepository routines;
  final DietStateRepository diet;

  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _user {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('Sessione scaduta. Accedi nuovamente.');
    return id;
  }

  Future<Map<String, double>> load(
    CompareSource source,
    DateTime start,
    DateTime end,
  ) async {
    final from = DateTime(start.year, start.month, start.day);
    final to = DateTime(end.year, end.month, end.day);
    switch (source) {
      case CompareSource.meditation:
        final entries = await routines.fetchEntries(
          start: from,
          endExclusive: to.add(const Duration(days: 1)),
        );
        return {
          for (final day in entries.entries)
            if (day.value['meditazione']?.status case final status?
                when status != RoutineStatus.unmarked)
              key(day.key): status == RoutineStatus.ok ? 1 : 0,
        };
      case CompareSource.dayConcentration:
        return _concentration(ConcentrationKind.day, from, to);
      case CompareSource.meditationConcentration:
        return _concentration(ConcentrationKind.meditation, from, to);
      case CompareSource.energy:
      case CompareSource.mood:
        return _emotions(source, from, to);
      case CompareSource.screen:
        final values = await daily.fetchScreenTimes(from, to);
        return {for (final e in values.entries) key(e.key): e.value.toDouble()};
      case CompareSource.movement:
        final values = await daily.fetchMovements(from, to);
        return {for (final e in values.entries) key(e.key): e.value.toDouble()};
      case CompareSource.calories:
        final state = await diet.fetchState();
        if (state == null) return {};
        final all = DietSheets.dailyCalories(state);
        return {
          for (final e in all.entries)
            if (e.key.compareTo(key(from)) >= 0 &&
                e.key.compareTo(key(to)) <= 0)
              e.key: e.value.toDouble(),
        };
    }
  }

  Future<Map<String, double>> _concentration(
    ConcentrationKind kind,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await client
        .from(kind.table)
        .select('reference_date,concentration')
        .eq('user_id', _user)
        .gte('reference_date', key(from))
        .lte('reference_date', key(to));
    return _mean([
      for (final row in rows)
        if ((row['concentration'] as num?) case final level?)
          ('${row['reference_date']}', level.toDouble()),
    ]);
  }

  Future<Map<String, double>> _emotions(
    CompareSource source,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await client
        .from('emotion_entries')
        .select('reference_date,emotion,energy')
        .eq('user_id', _user)
        .gte('reference_date', key(from))
        .lte('reference_date', key(to));
    final values = <(String, double)>[];
    for (final row in rows) {
      final date = '${row['reference_date']}';
      if (source == CompareSource.energy) {
        final level = switch (row['energy']) {
          'depleted' => 1.0,
          'low' => 2.0,
          'medium' => 3.0,
          'high' => 4.0,
          _ => null,
        };
        if (level != null) values.add((date, level));
      } else {
        final emotion = DailyEmotion.fromKey(row['emotion']);
        if (emotion == null || emotion == DailyEmotion.noData) continue;
        // Percentuale dei check-in del giorno con un'emozione positiva.
        values.add((date, emotion.tone == EmotionTone.good ? 100 : 0));
      }
    }
    return _mean(values);
  }

  static Map<String, double> _mean(List<(String, double)> values) {
    final sums = <String, (double, int)>{};
    for (final (date, v) in values) {
      final s = sums[date] ?? (0, 0);
      sums[date] = (s.$1 + v, s.$2 + 1);
    }
    return {for (final e in sums.entries) e.key: e.value.$1 / e.value.$2};
  }
}
