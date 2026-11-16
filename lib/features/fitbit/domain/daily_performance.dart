import 'dart:math' as math;

import 'fitbit_day.dart';

/// A transparent, preliminary performance snapshot calculated from the Fitbit
/// data already available to the dashboard. It deliberately keeps missing data
/// as missing: no metric is ever replaced with zero.
class DailyPerformance {
  const DailyPerformance({
    required this.recoveryScore,
    required this.cardioLoad,
    required this.sleepPerformance,
    required this.sleepDebtMinutes,
    required this.recoveryUsesPersonalBaseline,
  });

  static const sleepNeedMinutes = 480;

  final int? recoveryScore;
  final double? cardioLoad;
  final int? sleepPerformance;
  final int? sleepDebtMinutes;
  final bool recoveryUsesPersonalBaseline;

  factory DailyPerformance.fromFitbit(FitbitDay day) {
    final sleepScore = _sleepScore(day);
    final hrvScore = _hrvScore(day);
    final restingHeartRateScore = _restingHeartRateScore(day);
    final weightedScores = <({double score, double weight})>[
      if (hrvScore != null) (score: hrvScore, weight: 0.35),
      if (restingHeartRateScore != null)
        (score: restingHeartRateScore, weight: 0.25),
      if (sleepScore != null) (score: sleepScore, weight: 0.30),
    ];
    final canEstimateRecovery = weightedScores.length >= 2;
    final totalWeight = weightedScores.fold<double>(
      0,
      (sum, item) => sum + item.weight,
    );
    final recovery = canEstimateRecovery
        ? weightedScores.fold<double>(
                0,
                (sum, item) => sum + item.score * item.weight,
              ) /
              totalWeight
        : null;
    final zones = day.activeZoneMinutesByZone;
    final rawLoad = zones == null
        ? null
        : zones.fatBurn + zones.cardio * 2 + zones.peak * 3;
    final cardioLoad = rawLoad == null
        ? null
        : _clamp(21 * math.log(1 + rawLoad) / math.log(1 + 240), 0, 21);
    final sleepMinutes = day.sleepMinutes;
    return DailyPerformance(
      recoveryScore: recovery?.round(),
      cardioLoad: cardioLoad,
      sleepPerformance: sleepScore?.round(),
      sleepDebtMinutes: sleepMinutes == null
          ? null
          : math.max(0, sleepNeedMinutes - sleepMinutes),
      recoveryUsesPersonalBaseline:
          hrvScore != null || restingHeartRateScore != null,
    );
  }

  static double? _hrvScore(FitbitDay day) {
    final value = day.heartRateVariabilityMs;
    final baseline = _median(day.heartRateVariabilityTrend);
    if (value == null || baseline == null || baseline <= 0) return null;
    final deviation = (value - baseline) / baseline;
    return _clamp(50 + deviation * 300, 0, 100);
  }

  static double? _restingHeartRateScore(FitbitDay day) {
    final value = day.restingHeartRate;
    final baseline = _median(day.restingHeartRateTrend);
    if (value == null || baseline == null || baseline <= 0) return null;
    final deviation = (value - baseline) / baseline;
    return _clamp(50 - deviation * 400, 0, 100);
  }

  static double? _sleepScore(FitbitDay day) {
    final minutes = day.sleepMinutes;
    if (minutes == null) return null;
    final sufficiency = _clamp(minutes / sleepNeedMinutes, 0, 1);
    final efficiency = _clamp((day.sleepEfficiency ?? 0) / 100, 0, 1);
    return (sufficiency * 70 + efficiency * 30) * 100 / 100;
  }
}

double? _median(List<double> values) {
  final valid = values.where((value) => value.isFinite && value > 0).toList()
    ..sort();
  if (valid.length < 3) return null;
  final middle = valid.length ~/ 2;
  return valid.length.isOdd
      ? valid[middle]
      : (valid[middle - 1] + valid[middle]) / 2;
}

double _clamp(num value, num minimum, num maximum) =>
    value.clamp(minimum, maximum).toDouble();
