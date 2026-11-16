import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/routines/data/routine_repository.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/application/statistics_controller.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/routine_statistics.dart';

void main() {
  test('statistics respect activation dates and calculate streaks', () {
    final range = StatisticsRange(
      start: DateTime(2026, 8, 1),
      endExclusive: DateTime(2026, 8, 6),
    );
    final result = calculateRoutineStatistics(
      routineId: 'libro',
      range: range,
      history: [
        RoutineDefinition(
          id: 'libro',
          name: 'Libro',
          iconKey: 'book',
          position: 0,
          validFrom: DateTime(2026, 8, 2),
        ),
      ],
      entries: {
        DateTime(2026, 8, 2): const {
          'libro': RoutineEntry(status: RoutineStatus.ok),
        },
        DateTime(2026, 8, 3): const {
          'libro': RoutineEntry(status: RoutineStatus.ko),
        },
        DateTime(2026, 8, 4): const {
          'libro': RoutineEntry(status: RoutineStatus.ok),
        },
        DateTime(2026, 8, 5): const {
          'libro': RoutineEntry(status: RoutineStatus.ok),
        },
      },
    );

    expect(result.eligibleDays, 4);
    expect(result.recorded, 4);
    expect(result.completed, 3);
    expect(result.completionRate, .75);
    expect(result.currentStreak, 2);
    expect(result.longestStreak, 2);
  });

  test('previous range has the same duration and is contiguous', () {
    final range = StatisticsRange(
      start: DateTime(2026, 8, 11),
      endExclusive: DateTime(2026, 8, 18),
    );

    expect(range.previous.start, DateTime(2026, 8, 4));
    expect(range.previous.endExclusive, range.start);
  });

  test(
    'current month stops today and compares the same elapsed days',
    () async {
      final repository = _CapturingRepository();
      final controller = StatisticsController(
        repository: repository,
        history: [
          RoutineDefinition(
            id: 'libro',
            name: 'Libro',
            iconKey: 'book',
            position: 0,
            validFrom: DateTime(2026),
          ),
        ],
        initialDate: DateTime(2026, 8, 25),
        now: () => DateTime(2026, 8, 25, 18),
      );

      await controller.load();

      expect(controller.range.start, DateTime(2026, 8));
      expect(controller.range.endExclusive, DateTime(2026, 8, 26));
      expect(repository.requestedStart, DateTime(2026, 7));
      expect(controller.current?.eligibleDays, 25);
      expect(controller.previous?.eligibleDays, 25);
    },
  );
}

class _CapturingRepository implements RoutineRepository {
  DateTime? requestedStart;

  @override
  Future<RoutineDayRemoteState> fetchDay(DateTime date) {
    throw UnimplementedError();
  }

  @override
  Future<Map<DateTime, Map<String, RoutineEntry>>> fetchEntries({
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    requestedStart = start;
    return {};
  }

  @override
  Future<void> saveDay({
    required DateTime date,
    required List<RoutineDefinition> history,
    required Map<String, RoutineEntry> entries,
  }) {
    throw UnimplementedError();
  }
}
