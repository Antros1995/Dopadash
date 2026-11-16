import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine_progress.dart';

void main() {
  const routines = <RoutineDefinition>[
    RoutineDefinition(id: 'a', name: 'A', iconKey: 'task', position: 0),
    RoutineDefinition(id: 'b', name: 'B', iconKey: 'task', position: 1),
  ];

  test('combines routine score with the smartphone bonus', () {
    final progress = calculateRoutineProgress(
      definitions: routines,
      entries: const {
        'a': RoutineEntry(status: RoutineStatus.ok),
        'b': RoutineEntry(status: RoutineStatus.ko),
      },
      effectiveScreenTimeMinutes: 80,
    );

    expect(progress.completedCount, 1);
    expect(progress.earnedPoints, 3);
    expect(progress.maximumPoints, 4);
    expect(progress.percentage, 75);
  });

  test('an untouched day is not considered tracked', () {
    final progress = calculateRoutineProgress(
      definitions: routines,
      entries: const {},
    );

    expect(progress.isTracked, isFalse);
    expect(progress.percentage, 0);
  });
}
