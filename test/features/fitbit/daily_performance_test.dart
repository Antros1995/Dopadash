import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/domain/daily_performance.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/domain/fitbit_day.dart';

void main() {
  test('calculates a transparent initial performance snapshot', () {
    final performance = DailyPerformance.fromFitbit(_day());

    expect(performance.recoveryScore, inInclusiveRange(70, 100));
    expect(performance.recoveryUsesPersonalBaseline, isTrue);
    expect(performance.sleepPerformance, 92);
    expect(performance.sleepDebtMinutes, 39);
    expect(performance.cardioLoad, inInclusiveRange(0, 21));
  });

  test('keeps missing Fitbit values unavailable instead of using zero', () {
    final day = _day(
      heartRateVariabilityMs: null,
      restingHeartRate: null,
      sleepMinutes: null,
      sleepEfficiency: null,
      activeZoneMinutesByZone: null,
    );
    final performance = DailyPerformance.fromFitbit(day);

    expect(performance.recoveryScore, isNull);
    expect(performance.sleepPerformance, isNull);
    expect(performance.sleepDebtMinutes, isNull);
    expect(performance.cardioLoad, isNull);
  });
}

FitbitDay _day({
  double? heartRateVariabilityMs = 50,
  int? restingHeartRate = 55,
  int? sleepMinutes = 441,
  int? sleepEfficiency = 91,
  FitbitActiveZoneMinutes? activeZoneMinutesByZone =
      const FitbitActiveZoneMinutes(fatBurn: 35, cardio: 20, peak: 5),
}) => FitbitDay(
  date: '2026-09-08',
  finalized: true,
  syncedAt: DateTime.utc(2026, 9, 8),
  steps: 8000,
  distanceKm: 6,
  calories: 2000,
  activeMinutes: 45,
  activeZoneMinutesByZone: activeZoneMinutesByZone,
  restingHeartRate: restingHeartRate,
  sleepMinutes: sleepMinutes,
  sleepEfficiency: sleepEfficiency,
  heartRateVariabilityMs: heartRateVariabilityMs,
  heartRateVariabilityTrend: const [42, 44, 45, 43, 46],
  restingHeartRateTrend: const [59, 58, 60, 57, 58],
);
