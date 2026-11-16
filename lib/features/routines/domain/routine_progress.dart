import 'routine.dart';

class RoutineProgress {
  const RoutineProgress({
    required this.completedCount,
    required this.totalCount,
    required this.earnedPoints,
    required this.maximumPoints,
    required this.isTracked,
  });

  final int completedCount;
  final int totalCount;
  final double earnedPoints;
  final double maximumPoints;
  final bool isTracked;

  double get rate =>
      maximumPoints == 0 ? 0 : (earnedPoints / maximumPoints).clamp(0, 1);

  int get percentage => (rate * 100).round();
}

RoutineProgress calculateRoutineProgress({
  required List<RoutineDefinition> definitions,
  required Map<String, RoutineEntry> entries,
  int? effectiveScreenTimeMinutes,
}) {
  var completed = 0;
  var earned = 0.0;
  var maximum = 0.0;
  var isTracked = effectiveScreenTimeMinutes != null;

  for (final definition in definitions) {
    final entry = entries[definition.id] ?? const RoutineEntry();
    final detailScore = _selectedScore(definition, entry);
    maximum += detailScore != null && detailScore > definition.weight
        ? detailScore
        : definition.weight;
    if (!entry.isMarked) continue;
    isTracked = true;
    if (entry.isCompleted) completed += 1;
    earned += detailScore ?? (entry.isCompleted ? definition.weight : 0);
  }

  if (effectiveScreenTimeMinutes != null) {
    maximum += 2;
    earned += screenTimeBonus(effectiveScreenTimeMinutes);
  }

  return RoutineProgress(
    completedCount: completed,
    totalCount: definitions.length,
    earnedPoints: earned,
    maximumPoints: maximum,
    isTracked: isTracked,
  );
}

double? _selectedScore(RoutineDefinition definition, RoutineEntry entry) {
  final selectedId = entry.selectedDetailOptionId;
  if (selectedId == null) return null;
  final option = definition.detailOptions
      .where((candidate) => candidate.id == selectedId)
      .firstOrNull;
  return option?.score ??
      (option == null ? entry.selectedDetailScoreSnapshot : null);
}

double screenTimeBonus(int minutes) {
  if (minutes < 0) throw ArgumentError.value(minutes, 'minutes');
  if (minutes < 90) return 2;
  if (minutes < 120) return 1.6;
  if (minutes < 165) return 1.2;
  if (minutes < 180) return 0.8;
  if (minutes < 225) return 0.4;
  return 0;
}
