import '../../routines/domain/routine.dart';

enum StatisticsPeriod { week, month, year, custom }

extension StatisticsPeriodLabel on StatisticsPeriod {
  String get label => switch (this) {
    StatisticsPeriod.week => 'Settimana',
    StatisticsPeriod.month => 'Mese',
    StatisticsPeriod.year => 'Anno',
    StatisticsPeriod.custom => 'Personalizzato',
  };
}

class StatisticsRange {
  const StatisticsRange({required this.start, required this.endExclusive});

  final DateTime start;
  final DateTime endExclusive;

  int get days => endExclusive.difference(start).inDays;

  StatisticsRange get previous => StatisticsRange(
    start: start.subtract(Duration(days: days)),
    endExclusive: start,
  );
}

StatisticsRange statisticsRangeFor(
  StatisticsPeriod period,
  DateTime anchor, {
  StatisticsRange? customRange,
}) {
  final day = dateOnly(anchor);
  return switch (period) {
    StatisticsPeriod.week => StatisticsRange(
      start: day.subtract(Duration(days: day.weekday - 1)),
      endExclusive: day
          .subtract(Duration(days: day.weekday - 1))
          .add(const Duration(days: 7)),
    ),
    StatisticsPeriod.month => StatisticsRange(
      start: DateTime(day.year, day.month),
      endExclusive: DateTime(day.year, day.month + 1),
    ),
    StatisticsPeriod.year => StatisticsRange(
      start: DateTime(day.year),
      endExclusive: DateTime(day.year + 1),
    ),
    StatisticsPeriod.custom =>
      customRange ??
          StatisticsRange(
            start: day,
            endExclusive: day.add(const Duration(days: 1)),
          ),
  };
}

class RoutineDailyPoint {
  const RoutineDailyPoint({
    required this.date,
    required this.eligible,
    required this.status,
  });

  final DateTime date;
  final bool eligible;
  final RoutineStatus status;
}

class RoutineStatistics {
  const RoutineStatistics({
    required this.completed,
    required this.recorded,
    required this.eligibleDays,
    required this.currentStreak,
    required this.longestStreak,
    required this.points,
  });

  final int completed;
  final int recorded;
  final int eligibleDays;
  final int currentStreak;
  final int longestStreak;
  final List<RoutineDailyPoint> points;

  double get completionRate => eligibleDays == 0 ? 0 : completed / eligibleDays;
}

RoutineStatistics calculateRoutineStatistics({
  required String routineId,
  required StatisticsRange range,
  required List<RoutineDefinition> history,
  required Map<DateTime, Map<String, RoutineEntry>> entries,
}) {
  final points = <RoutineDailyPoint>[];
  var completed = 0;
  var recorded = 0;
  var eligible = 0;
  var currentRun = 0;
  var longestRun = 0;

  for (
    var date = range.start;
    date.isBefore(range.endExclusive);
    date = date.add(const Duration(days: 1))
  ) {
    final isEligible = history.any(
      (definition) => definition.id == routineId && definition.isValidOn(date),
    );
    final entry = entries[dateOnly(date)]?[routineId] ?? const RoutineEntry();
    points.add(
      RoutineDailyPoint(date: date, eligible: isEligible, status: entry.status),
    );
    if (!isEligible) continue;
    eligible += 1;
    if (entry.isMarked) recorded += 1;
    if (entry.isCompleted) {
      completed += 1;
      currentRun += 1;
      if (currentRun > longestRun) longestRun = currentRun;
    } else {
      currentRun = 0;
    }
  }

  var currentStreak = 0;
  for (final point in points.reversed) {
    if (!point.eligible) continue;
    if (point.status != RoutineStatus.ok) break;
    currentStreak += 1;
  }

  return RoutineStatistics(
    completed: completed,
    recorded: recorded,
    eligibleDays: eligible,
    currentStreak: currentStreak,
    longestStreak: longestRun,
    points: List.unmodifiable(points),
  );
}
