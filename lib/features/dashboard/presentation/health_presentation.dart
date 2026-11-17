import '../../fitbit/domain/daily_performance.dart';
import '../../fitbit/domain/fitbit_day.dart';
import '../../../core/i18n/i18n.dart';

/// UI policy only: never changes stored records or export calculations.
class HealthPresentation {
  HealthPresentation(this.day, {required this.isToday});
  final FitbitDay day;
  final bool isToday;
  static bool positive(num? value) =>
      value != null && value.isFinite && value > 0;
  int? get sleepScore =>
      positive(day.sleepMinutes) &&
          positive(day.sleepEfficiency) &&
          day.sleepEfficiency! <= 100
      ? DailyPerformance.fromFitbit(day).sleepPerformance
      : null;
  int? get recovery {
    // Undated trend arrays cannot safely establish a historical baseline.
    if (!isToday || sleepScore == null) return null;
    final hasHrv =
        positive(day.heartRateVariabilityMs) &&
        day.heartRateVariabilityTrend.where(positive).length >= 5;
    final hasHr =
        positive(day.restingHeartRate) &&
        day.restingHeartRateTrend.where(positive).length >= 5;
    return hasHrv || hasHr
        ? DailyPerformance.fromFitbit(day).recoveryScore
        : null;
  }

  double? get load {
    final zones = day.activeZoneMinutesByZone;
    if (zones == null ||
        zones.fatBurn < 0 ||
        zones.cardio < 0 ||
        zones.peak < 0 ||
        zones.fatBurn + zones.cardio + zones.peak == 0) {
      return null;
    }
    return DailyPerformance.fromFitbit(day).cardioLoad;
  }

  List<String> get insights {
    final result = <String>[];
    void compare(num? current, List<double> source, String name, String unit) {
      if (!isToday || !positive(current)) return;
      final values = source.where(positive).toList();
      if (values.length < 5) return;
      final average = values.reduce((a, b) => a + b) / values.length;
      final delta = current! - average;
      result.add(
        tr(
          '$name ${delta >= 0 ? '+' : '−'}${delta.abs().toStringAsFixed(0)} $unit rispetto alla media dei ${values.length} campioni ricevuti.',
          '$name ${delta >= 0 ? '+' : '−'}${delta.abs().toStringAsFixed(0)} $unit vs. the average of the ${values.length} samples received.',
        ),
      );
    }

    compare(
      day.heartRateVariabilityMs,
      day.heartRateVariabilityTrend,
      'HRV',
      'ms',
    );
    compare(
      day.restingHeartRate,
      day.restingHeartRateTrend,
      tr('FC a riposo', 'Resting HR'),
      'bpm',
    );
    compare(
      day.sleepMinutes,
      day.sleepMinutesTrend,
      tr('Sonno', 'Sleep'),
      'min',
    );
    if (result.isEmpty && positive(day.sleepMinutes)) {
      result.add(
        tr(
          'Sonno registrato: ${durationLabel(day.sleepMinutes!)}.',
          'Sleep recorded: ${durationLabel(day.sleepMinutes!)}.',
        ),
      );
      final deep = day.sleepDetails?.stageMinutes.deep;
      if (positive(deep)) {
        result.add(
          tr(
            '${durationLabel(deep!)} di sonno profondo rilevato.',
            '${durationLabel(deep)} of deep sleep detected.',
          ),
        );
      }
    }
    if (result.isEmpty && day.steps > 0) {
      result.add(
        tr(
          '${day.steps} passi registrati per questa giornata.',
          '${day.steps} steps recorded for this day.',
        ),
      );
    }
    return result.take(3).toList();
  }
}

String durationLabel(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';
