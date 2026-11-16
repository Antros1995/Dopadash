import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/application/body_statistics_controller.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/body_statistics.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/perception_statistics.dart';
import 'body_statistics_test.dart' show MemoryStatisticsRepository, experiment;

PerceptionEntry emotion(
  String id,
  String date,
  String kind,
  double intensity,
) => PerceptionEntry.fromJson({
  'id': id,
  'reference_date': date,
  'emotion': kind,
  'intensity': intensity,
  'energy': 'medium',
  'recorded_at': '${date}T21:00:00Z',
});

void main() {
  test('daily means retain the diary scale, date and missing observations', () {
    final entries = [
      emotion('a', '2026-10-01', 'calm', 1),
      emotion('b', '2026-10-01', 'calm', 5),
      emotion('c', '2026-10-01', 'stressed', 4),
      emotion('d', '2026-10-02', 'calm', 5),
      emotion('e', '2026-10-03', 'no_data', 1),
      emotion('f', '2026-10-04', 'calm', 0),
      emotion('g', '2026-10-04', 'calm', 6),
    ];
    final a = PerceptionAnalysis(entries, emotion: 'calm');
    expect(a.entries.length, 3);
    expect(a.dailyMeans, {'2026-10-01': 3, '2026-10-02': 5});
    expect(a.frequencies, {'calm': 3});
    expect(BodySummary(a.dailyMeans.values, 4).mean, 4);
    expect(PerceptionAnalysis(entries).frequencies, {'calm': 3, 'stressed': 1});
    expect(entries.first.date, DateTime.utc(2026, 10, 1));
    expect(entries.first.label, 'Calmo');
    expect(entries.first.energyLabel, 'Media');
    expect(entries.first.toJson()['reference_date'], '2026-10-01');
    expect(BodyMetric.calm.format(3), '3,0 /5');
  });

  test(
    'experiments use calm emotions only, with independent days and exclusions',
    () {
      final e = experiment();
      final entries = [
        emotion('a', '2026-10-01', 'calm', 1),
        emotion('b', '2026-10-01', 'calm', 5),
        emotion('c', '2026-10-02', 'calm', 5),
        emotion('d', '2026-10-03', 'calm', 2),
        emotion('e', '2026-10-03', 'stressed', 5),
        emotion('f', '2026-10-04', 'happy', 5),
        emotion('g', '2026-10-05', 'calm', 5),
      ];
      final logs = [
        ExperimentLog(
          experimentId: 'test',
          date: DateTime.utc(2026, 10, 3),
          calm: 10,
          context: {'alcohol': true},
        ),
      ];
      final a = ExperimentComparison(
        experiment: e,
        days: [],
        logs: logs,
        perceptions: entries,
        today: DateTime(2026, 10, 4),
      );
      expect(a.summary(e.baseline, BodyMetric.calm).mean, 4);
      expect(a.summary(e.baseline, BodyMetric.calm).count, 2);
      expect(a.summary(e.range, BodyMetric.calm).mean, 2);
      expect(a.value(DateTime.utc(2026, 10, 4), BodyMetric.calm), isNull);
      expect(a.value(DateTime.utc(2026, 10, 5), BodyMetric.calm), isNull);
      expect(a.completed, 0);
      final filtered = ExperimentComparison(
        experiment: e,
        days: [],
        logs: logs,
        perceptions: entries,
        today: DateTime(2026, 10, 4),
        excludedFactors: {'alcohol'},
      );
      expect(filtered.summary(e.range, BodyMetric.calm).mean, isNull);
      expect(filtered.excludedCount(e.range), 1);
      expect(a.summary(e.range, BodyMetric.calm).mean, 2);
      final withoutCalm = BodyExperiment(
        id: 'other',
        name: 'Test',
        range: e.range,
        baseline: e.baseline,
        secondary: const [],
      );
      expect(withoutCalm.metrics, contains(BodyMetric.calm));
    },
  );

  test(
    'controller loads, refreshes and exports emotions and restores perception filters',
    () async {
      final repo = MemoryStatisticsRepository()
        ..perceptions = [emotion('a', '2025-02-01', 'calm', 4)]
        ..experiments = [experiment()]
        ..preferences = {
          'section': 'Percezione',
          'period': 'all',
          'perceptionEmotion': 'calm',
          'selectedId': 'test',
        };
      final c = BodyStatisticsController(
        repository: repo,
        clock: () => DateTime(2026, 10, 4),
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.range.start, DateTime.utc(2025, 2, 1));
      expect(c.perceptionEmotion, 'calm');
      expect(c.experimentMetric, BodyMetric.calm);
      repo.perceptions = [emotion('b', '2026-10-03', 'calm', 2)];
      await c.loadPerceptions();
      expect(c.analysis!.summary(c.selected!.range, BodyMetric.calm).mean, 2);
      expect(c.preferences['perceptionEmotion'], 'calm');
      await c.persist();
      final restored = BodyStatisticsController(repository: repo);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.perceptionEmotion, 'calm');
    },
  );

  test(
    'diary read errors stay visible without hiding other statistics and can recover',
    () async {
      final repo = _FailingPerceptionRepository();
      final c = BodyStatisticsController(repository: repo);
      addTearDown(c.dispose);
      await c.load();
      expect(c.loaded, isTrue);
      expect(c.error, isNull);
      expect(c.perceptionError, isNotNull);
      repo.fail = false;
      repo.perceptions = [emotion('a', '2026-10-03', 'calm', 4)];
      await c.loadPerceptions();
      expect(c.perceptionError, isNull);
      expect(c.perceptions.single.intensity, 4);
    },
  );
}

class _FailingPerceptionRepository extends MemoryStatisticsRepository {
  bool fail = true;
  @override
  Future<List<PerceptionEntry>> loadPerceptions() async {
    if (fail) throw StateError('Diario non disponibile');
    return super.loadPerceptions();
  }
}
