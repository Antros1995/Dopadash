import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/application/body_statistics_controller.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/data/body_statistics_repository.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/body_statistics.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/perception_statistics.dart';

BodyDay day(
  String date, {
  double? hrv,
  double? steps,
  Map<String, bool>? availability,
}) => BodyDay({
  'date': date,
  'heartRateVariabilityMs': hrv,
  'steps': steps,
  'availability': ?availability,
});
BodyExperiment experiment({
  String id = 'test',
  ExperimentStatus status = ExperimentStatus.running,
}) => BodyExperiment(
  id: id,
  name: 'Pratica',
  range: BodyRange(DateTime(2026, 10, 3), DateTime(2026, 10, 4)),
  baseline: BodyRange(DateTime(2026, 10, 1), DateTime(2026, 10, 2)),
  status: status,
);

class MemoryStatisticsRepository implements BodyStatisticsRepository {
  List<BodyDay> days = [];
  List<PerceptionEntry> perceptions = [];
  List<BodyExperiment> experiments = [];
  Map<String, List<ExperimentLog>> logs = {};
  Map<String, dynamic> preferences = {};
  Completer<List<ExperimentLog>>? pending;
  bool failSave = false;
  @override
  Future<List<BodyDay>> loadDays() async => days;
  @override
  Future<List<PerceptionEntry>> loadPerceptions() async => perceptions;
  @override
  Future<List<BodyExperiment>> loadExperiments() async => experiments;
  @override
  Future<List<ExperimentLog>> loadLogs(String id) =>
      pending?.future ?? Future.value(logs[id] ?? []);
  @override
  Future<Map<String, dynamic>> loadPreferences() async => preferences;
  @override
  Future<void> savePreferences(Map<String, dynamic> p) async {
    if (failSave) throw StateError('save failed');
    preferences = p;
  }

  @override
  Future<void> syncHistory() async {}
  @override
  Future<void> recoverDays(
    List<DateTime> dates, {
    required bool Function() cancelled,
    required void Function(int, int) onProgress,
  }) async {}
  @override
  Future<BodyExperiment> saveExperiment(BodyExperiment e) async {
    final saved = BodyExperiment.fromJson({...e.toJson(), 'id': e.id ?? 'new'});
    experiments = [saved, ...experiments.where((v) => v.id != saved.id)];
    return saved;
  }

  @override
  Future<void> saveLog(ExperimentLog l) async {
    logs[l.experimentId] = [
      l,
      ...?logs[l.experimentId]?.where(
        (v) => statsKey(v.date) != statsKey(l.date),
      ),
    ];
  }

  @override
  Future<void> deleteLog(ExperimentLog l) async {
    logs[l.experimentId]?.removeWhere(
      (v) => statsKey(v.date) == statsKey(l.date),
    );
  }
}

void main() {
  test(
    'statistics recover an unsuccessful initial load in the same session',
    () async {
      final repo = _RecoveringStatisticsRepository()
        ..days = [day('2026-10-19', hrv: 44)];
      final c = BodyStatisticsController(
        repository: repo,
        clock: () => DateTime(2026, 10, 19),
      );
      await c.load();
      expect(c.loaded, isFalse);
      expect(c.error, isNotNull);
      repo.offline = false;
      await c.synchronize();
      expect(c.loaded, isTrue);
      expect(c.error, isNull);
      expect(c.days.single.value(BodyMetric.hrv), 44);
      c.dispose();
    },
  );
  test(
    'missing and ambiguous legacy zero are not observations; verified zero is valid',
    () {
      expect(day('2026-10-01', steps: 0).value(BodyMetric.steps), isNull);
      expect(
        day(
          '2026-10-01',
          steps: 0,
          availability: {'steps': true},
        ).value(BodyMetric.steps),
        0,
      );
      expect(
        day(
          '2026-10-01',
          steps: 123,
          availability: {'steps': false},
        ).value(BodyMetric.steps),
        isNull,
      );
      final s = BodySummary([null, 0, 4], 4);
      expect(s.count, 2);
      expect(s.mean, 2);
      expect(s.total, 4);
      expect(s.coverage, .5);
      expect(s.sd, closeTo(2.828427, 0.00001));
      expect(BodySummary([null], 1).total, isNull);
    },
  );
  test('calendar ranges cross DST with equal-length previous periods', () {
    final range = BodyRange(DateTime(2026, 10, 24), DateTime(2026, 10, 26));
    expect(range.days, 3);
    expect(range.dates.length, 3);
    expect(range.previous.days, 3);
    expect(statsKey(range.previous.start), '2026-10-21');
    expect(statsKey(range.previous.end), '2026-10-23');
    expect(romeWallTime(DateTime.utc(2026, 10, 25, 0, 30)).hour, 2);
    expect(romeWallTime(DateTime.utc(2026, 10, 25, 1, 30)).hour, 2);
    expect(romeWallTime(DateTime.utc(2026, 3, 29, 0, 30)).hour, 1);
    expect(romeWallTime(DateTime.utc(2026, 3, 29, 1, 30)).hour, 3);
  });
  test(
    'moving means retain missing dates and partial weeks remain recognizable',
    () {
      expect(movingAverage([10, 20, null, 40]), [10, 15, null, 70 / 3]);
      final buckets = weeklyBuckets(
        [day('2026-10-04', steps: 10), day('2026-10-05', steps: 20)],
        BodyRange(DateTime(2026, 10, 4), DateTime(2026, 10, 6)),
        BodyMetric.steps,
      );
      expect(buckets.length, 2);
      expect(buckets[0].summary.total, 10);
      expect(buckets[1].summary.total, 20);
      expect(buckets.every((b) => b.partial), isTrue);
    },
  );
  test(
    'experiment comparisons never infer practice, and filters are reversible',
    () {
      final e = experiment();
      final days = [
        day('2026-10-01', hrv: 30),
        day('2026-10-02', hrv: 50),
        day('2026-10-03', hrv: 45),
        day('2026-10-04', hrv: 55),
      ];
      final logs = [
        ExperimentLog(
          experimentId: 'test',
          date: DateTime.utc(2026, 10, 3),
          sessionStatus: 'partial',
          calm: 0,
          context: {'alcohol': true},
        ),
      ];
      final a = ExperimentComparison(
        experiment: e,
        days: days,
        logs: logs,
        perceptions: [
          PerceptionEntry(
            id: 'calm',
            date: DateTime.utc(2026, 10, 3),
            emotion: 'calm',
            intensity: 2,
            energy: 'medium',
            recordedAt: DateTime.utc(2026, 10, 3, 18),
          ),
        ],
        today: DateTime(2026, 10, 4),
      );
      expect(a.completed, 0);
      expect(a.summary(e.baseline, BodyMetric.hrv).mean, 40);
      expect(a.summary(e.range, BodyMetric.hrv).mean, 50);
      expect(a.summary(e.range, BodyMetric.calm).mean, 2);
      expect(a.summary(e.baseline, BodyMetric.calm).mean, isNull);
      expect(a.observation(BodyMetric.hrv), contains('+10 ms'));
      expect(a.observation(BodyMetric.calm), contains('Dati insufficienti'));
      final filtered = ExperimentComparison(
        experiment: e,
        days: days,
        logs: logs,
        today: DateTime(2026, 10, 4),
        excludedFactors: {'alcohol'},
      );
      expect(filtered.excludedCount(e.range), 1);
      expect(filtered.summary(e.range, BodyMetric.hrv).mean, 55);
      expect(a.summary(e.range, BodyMetric.hrv).mean, 50);
    },
  );
  test(
    'ongoing comparisons ignore future values and count elapsed days only',
    () {
      final e = experiment();
      final a = ExperimentComparison(
        experiment: e,
        days: [day('2026-10-03', hrv: 40), day('2026-10-04', hrv: 90)],
        logs: [],
        today: DateTime(2026, 10, 3),
      );
      expect(a.availableDays, 1);
      expect(a.summary(e.range, BodyMetric.hrv).mean, 40);
      expect(a.summary(e.range, BodyMetric.hrv).expected, 1);
      expect(a.provisional, isTrue);
      expect(BodyMetric.calm.format(1.4, delta: true), '+1,4 punti');
      expect(BodyMetric.efficiency.format(-3, delta: true), '-3 punti');
    },
  );
  test(
    'preferences reconstruct the same periods, filters and selected metric after reload',
    () async {
      final repo = MemoryStatisticsRepository();
      final c = BodyStatisticsController(
        repository: repo,
        clock: () => DateTime(2026, 10, 17),
      );
      await c.load();
      c.change(() {
        c.period = BodyPeriod.custom;
        c.customRange = BodyRange(DateTime(2026, 9, 1), DateTime(2026, 9, 12));
        c.customComparison = BodyRange(
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 12),
        );
        c.excludedFactors = {'illness'};
        c.moving = false;
        c.section = 'Sonno';
        c.heartMetric = BodyMetric.hrv;
        c.averageHeartDay = true;
      });
      await c.persist();
      final second = BodyStatisticsController(repository: repo);
      await second.load();
      expect(second.range.toJson(), c.range.toJson());
      expect(second.comparisonRange!.toJson(), c.comparisonRange!.toJson());
      expect(second.excludedFactors, {'illness'});
      expect(second.moving, isFalse);
      expect(second.section, 'Sonno');
      expect(second.heartMetric, BodyMetric.hrv);
      expect(second.averageHeartDay, isTrue);
      c.dispose();
      second.dispose();
    },
  );
  test(
    'failed writes stay visible and saving a diary entry recalculates comparisons',
    () async {
      final repo = MemoryStatisticsRepository()..experiments = [experiment()];
      final c = BodyStatisticsController(
        repository: repo,
        clock: () => DateTime(2026, 10, 4),
      );
      await c.load();
      await c.selectExperiment('test');
      repo.failSave = true;
      await c.persist();
      expect(c.saveError, isNotNull);
      repo.failSave = false;
      await c.persist();
      expect(c.saveError, isNull);
      expect(
        await c.saveLog(
          ExperimentLog(
            experimentId: 'test',
            date: DateTime.utc(2026, 10, 3),
            sessionStatus: 'completed',
            stress: 6,
          ),
        ),
        isTrue,
      );
      expect(c.analysis!.completed, 1);
      expect(c.analysis!.summary(c.selected!.range, BodyMetric.stress).mean, 6);
      c.dispose();
    },
  );
  test(
    'changing experiment while a request is in flight cannot mix diary records',
    () async {
      final repo = MemoryStatisticsRepository()
        ..experiments = [experiment(id: 'a'), experiment(id: 'b')];
      final c = BodyStatisticsController(repository: repo);
      await c.load();
      final a = Completer<List<ExperimentLog>>(),
          b = Completer<List<ExperimentLog>>();
      repo.pending = a;
      final loadingA = c.selectExperiment('a');
      repo.pending = b;
      final loadingB = c.selectExperiment('b');
      b.complete([
        ExperimentLog(
          experimentId: 'b',
          date: DateTime.utc(2026, 10, 3),
          calm: 7,
        ),
      ]);
      await loadingB;
      a.complete([
        ExperimentLog(
          experimentId: 'a',
          date: DateTime.utc(2026, 10, 3),
          calm: 1,
        ),
      ]);
      await loadingA;
      expect(c.selectedId, 'b');
      expect(c.logs.single.calm, 7);
      c.dispose();
    },
  );
}

class _RecoveringStatisticsRepository extends MemoryStatisticsRepository {
  bool offline = true;
  @override
  Future<List<BodyDay>> loadDays() async {
    if (offline) throw StateError('offline');
    return super.loadDays();
  }
}
