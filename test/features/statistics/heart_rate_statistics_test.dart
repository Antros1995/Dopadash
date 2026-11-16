import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/body_statistics.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/heart_rate_statistics.dart';

Map<String, dynamic> point(String time, num average) => {
  'startTime': time,
  'average': average,
};
BodyDay heartDay(String date, List<Object?> points) => BodyDay({
  'date': date,
  'heartProfile': points,
  'restingHeartRate': 55,
  'finalized': true,
});

void main() {
  test(
    'period means use every selected day rather than only the final date',
    () {
      final stats = HeartRateStatistics([
        heartDay('2026-10-01', [
          point('2026-10-01T08:00:00Z', 60),
          point('2026-10-01T08:30:00Z', 100),
        ]),
        heartDay('2026-10-03', [point('2026-10-03T08:00:00Z', 120)]),
        heartDay('2026-10-04', [point('2026-10-04T08:00:00Z', 200)]),
      ], BodyRange(DateTime(2026, 10, 1), DateTime(2026, 10, 3)));
      expect(stats.dailyMeans, [80, null, 120]);
      expect(
        stats.summary.mean,
        100,
      ); // equal date weights, not 3 pooled samples
      expect(stats.summary.count, 2);
      expect(stats.summary.expected, 3);
      expect(stats.count, 3);
      expect(stats.clockMeans[20], 90); // 10:00 Rome, both selected dates
      expect(stats.clockMeans[21], 100);
      expect(stats.clockSummaries[20].count, 2);
      expect(stats.clockMeans[0], isNull);
    },
  );
  test(
    'invalid values, duplicate instants and samples attributed to another Rome day are excluded',
    () {
      final stats = HeartRateStatistics([
        heartDay('2026-10-01', [
          point('2026-09-30T22:00:00Z', 60), // October 1 midnight Rome
          point('2026-09-30T22:00:00+00:00', 60),
          point('2026-10-01T22:00:00Z', 150), // October 2 in Rome
          point('2026-10-01T08:00:00Z', 0),
          point('2026-10-01T09:00:00Z', double.nan),
          point('2026-10-01T10:00:00Z', -5), point('2026-10-01T11:00:00', 200),
          {'startTime': 'invalid', 'average': 100}, {'average': 80}, null,
        ]),
      ], BodyRange(DateTime(2026, 10, 1), DateTime(2026, 10, 1)));
      expect(stats.count, 1);
      expect(stats.summary.mean, 60);
      expect(stats.intradayMeans.first, 60);
      expect(stats.intradayMeans.skip(1).every((v) => v == null), isTrue);
    },
  );
  test(
    'empty intraday data stays missing and never falls back to resting heart rate',
    () {
      final stats = HeartRateStatistics([
        heartDay('2026-10-01', []),
      ], BodyRange(DateTime(2026, 10, 1), DateTime(2026, 10, 2)));
      expect(stats.dailyMeans, [null, null]);
      expect(stats.summary.mean, isNull);
      expect(stats.clockMeans.every((v) => v == null), isTrue);
    },
  );
  test(
    'autumn clock profile averages repeated hours within each date before averaging dates',
    () {
      final stats = HeartRateStatistics([
        heartDay('2026-10-25', [
          point('2026-10-25T00:00:00Z', 40),
          point('2026-10-25T01:00:00Z', 80),
        ]),
        heartDay('2026-10-26', [point('2026-10-26T01:00:00Z', 100)]),
      ], BodyRange(DateTime(2026, 10, 25), DateTime(2026, 10, 26)));
      expect(stats.clockMeans[4], 80);
      expect(stats.clockSummaries[4].count, 2);
      final autumn = HeartRateStatistics([
        heartDay('2026-10-25', [
          point('2026-10-25T00:00:00Z', 40),
          point('2026-10-25T01:00:00Z', 80),
        ]),
      ], BodyRange(DateTime(2026, 10, 25), DateTime(2026, 10, 25)));
      expect(autumn.intradayTimes.length, 50);
      expect(autumn.intradayMeans.whereType<double>().toList(), [40, 80]);
      expect(
        autumn.intradayLabels,
        containsAll(['02:00 UTC+2', '02:00 UTC+1']),
      );
      final spring = HeartRateStatistics(
        [],
        BodyRange(DateTime(2026, 3, 29), DateTime(2026, 3, 29)),
      );
      expect(spring.intradayTimes.length, 46);
      expect(spring.intradayLabels, isNot(contains('02:00')));
    },
  );
  test(
    'moving the range and selecting a separate reference recomputes means from that interval',
    () {
      final days = [
        heartDay('2026-09-30', [point('2026-09-30T08:00:00Z', 50)]),
        heartDay('2026-10-01', [point('2026-10-01T08:00:00Z', 70)]),
      ];
      final current = HeartRateStatistics(
        days,
        BodyRange(DateTime(2026, 10, 1), DateTime(2026, 10, 1)),
      );
      final previous = HeartRateStatistics(days, current.range.previous);
      expect(current.summary.mean, 70);
      expect(previous.summary.mean, 50);
      expect(current.clockMeans[20], 70);
      expect(previous.clockMeans[20], 50);
    },
  );
}
