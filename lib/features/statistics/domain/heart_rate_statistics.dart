import 'body_statistics.dart';

class HeartRateSample {
  const HeartRateSample(this.time, this.bpm);
  final DateTime time;
  final double bpm;
  DateTime get local => romeWallTime(time);
  int get clockSlot => local.hour * 2 + local.minute ~/ 30;
}

/// The backend supplies means over 30-minute intervals, not individual beats.
/// Missing intervals remain absent; resting heart rate is a separate metric.
class HeartRateStatistics {
  HeartRateStatistics(Iterable<BodyDay> days, this.range) {
    for (final day in days.where((d) => range.contains(d.date))) {
      final unique = <int, HeartRateSample>{};
      for (final raw in (day.data['heartProfile'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final bpm = raw['average'], timestamp = raw['startTime'];
        if (bpm is! num || !bpm.isFinite || bpm <= 0 || timestamp is! String) {
          continue;
        }
        // An explicit UTC offset is necessary to attribute a sample to Rome.
        if (!RegExp(
          r'(Z|[+-]\d{2}:?\d{2})$',
          caseSensitive: false,
        ).hasMatch(timestamp)) {
          continue;
        }
        final time = DateTime.tryParse(timestamp)?.toUtc();
        if (time == null || statsDate(romeWallTime(time)) != day.date) continue;
        unique[time.millisecondsSinceEpoch] = HeartRateSample(
          time,
          bpm.toDouble(),
        );
      }
      samples[statsKey(day.date)] = unique.values.toList()
        ..sort((a, b) => a.time.compareTo(b.time));
    }
  }
  final BodyRange range;
  final Map<String, List<HeartRateSample>> samples = {};
  List<HeartRateSample> samplesAt(DateTime day) =>
      samples[statsKey(day)] ?? const [];
  int get count => samples.values.fold(0, (sum, points) => sum + points.length);
  List<double?> get dailyMeans => [
    for (final day in range.dates)
      BodySummary(samplesAt(day).map((p) => p.bpm), 0).mean,
  ];
  BodySummary get summary => BodySummary(dailyMeans, range.days);
  List<String> get dailyDetails => [
    for (final day in range.dates)
      '${samplesAt(day).length} intervalli di 30 min disponibili',
  ];
  late final List<BodySummary> clockSummaries = List.generate(
    48,
    (slot) => BodySummary([
      // Average repeated clock slots within each day first (autumn DST).
      // Each contributing date then has equal weight in the typical day.
      for (final day in range.dates)
        BodySummary(
          samplesAt(day).where((p) => p.clockSlot == slot).map((p) => p.bpm),
          0,
        ).mean,
    ], range.days),
  );
  List<double?> get clockMeans => clockSummaries.map((s) => s.mean).toList();
  List<String> get clockDetails => clockSummaries
      .map((s) => '${s.count} / ${range.days} giorni con dati in questa fascia')
      .toList();
  static String clockLabel(int slot) =>
      '${(slot ~/ 2).toString().padLeft(2, '0')}:${slot.isEven ? '00' : '30'}';

  /// Civil midnight converted to an instant, including 23/25-hour DST dates.
  static DateTime _midnightUtc(DateTime day) {
    final label = statsDate(day);
    return label.subtract(Duration(hours: romeWallTime(label).hour));
  }

  late final List<DateTime> intradayTimes = [
    for (
      var t = _midnightUtc(range.start);
      t.isBefore(_midnightUtc(range.start.add(const Duration(days: 1))));
      t = t.add(const Duration(minutes: 30))
    )
      t,
  ];
  late final List<BodySummary> intradaySummaries = [
    for (final t in intradayTimes)
      BodySummary(
        samplesAt(range.start)
            .where(
              (p) =>
                  !p.time.isBefore(t) &&
                  p.time.isBefore(t.add(const Duration(minutes: 30))),
            )
            .map((p) => p.bpm),
        0,
      ),
  ];
  List<double?> get intradayMeans =>
      intradaySummaries.map((s) => s.mean).toList();
  List<String> get intradayLabels => intradayTimes.map((t) {
    final local = romeWallTime(t);
    final label = clockLabel(local.hour * 2 + local.minute ~/ 30);
    return intradayTimes.length == 50 && local.hour == 2
        ? '$label UTC+${local.difference(t).inHours}'
        : label;
  }).toList();
}
