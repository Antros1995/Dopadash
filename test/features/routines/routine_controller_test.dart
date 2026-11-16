import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/routines/application/routine_controller.dart';
import 'package:monitoraggio_personale_desktop/features/routines/data/routine_repository.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine.dart';

void main() {
  test(
    'an unsaved routine remains visible when leaving and returning to its day',
    () async {
      final repository = _RealtimeRoutineRepository()..failSave = true;
      final date = DateTime(2026, 10, 19);
      final c = RoutineController(repository: repository, initialDate: date);
      await c.load();
      await c.toggleRoutine('meditazione');
      await c.selectDate(date.subtract(const Duration(days: 1)));
      await c.selectDate(date);
      expect(c.entryFor('meditazione').status, RoutineStatus.ok);
      expect(c.syncError, isNotNull);
      c.dispose();
      await repository.changes.close();
    },
  );
  test(
    'failed routine writes survive refresh and retry when connectivity returns',
    () async {
      final repository = _RealtimeRoutineRepository()..failSave = true;
      final controller = RoutineController(repository: repository);
      await controller.load();
      await controller.toggleRoutine('meditazione');
      expect(controller.syncError, isNotNull);
      await controller.refreshSilently();
      expect(controller.entryFor('meditazione').status, RoutineStatus.ok);
      expect(
        repository.fetches,
        1,
        reason: 'Never replace an unsaved change with the old remote day',
      );
      repository.failSave = false;
      await controller.refreshSilently();
      expect(controller.syncError, isNull);
      expect(controller.entryFor('meditazione').status, RoutineStatus.ok);
      expect(repository.remoteEntry.status, RoutineStatus.ok);
      expect(controller.isSaving, isFalse);
      controller.dispose();
      await repository.changes.close();
    },
  );

  testWidgets('a stalled routine read does not prevent the next refresh', (
    tester,
  ) async {
    final repository = _RealtimeRoutineRepository();
    final controller = RoutineController(repository: repository);
    await controller.load();
    final lateRead = Completer<RoutineDayRemoteState>();
    repository.pending = lateRead;
    final refresh = controller.refreshSilently();
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await refresh;
    repository.pending = null;
    repository.remoteEntry = const RoutineEntry(status: RoutineStatus.ok);
    await controller.refreshSilently();
    expect(controller.entryFor('meditazione').status, RoutineStatus.ok);
    lateRead.complete(
      const RoutineDayRemoteState(
        history: [],
        entries: {},
        effectiveScreenTimeMinutes: null,
      ),
    );
    await tester.pump();
    expect(controller.entryFor('meditazione').status, RoutineStatus.ok);
    controller.dispose();
    await repository.changes.close();
  });
  test('toggle updates immediately and serializes remote saves', () async {
    final repository = _FakeRoutineRepository();
    final controller = RoutineController(
      repository: repository,
      initialDate: DateTime(2026, 8, 25),
      now: () => DateTime(2026, 8, 25, 9, 30),
      initialHistory: const [
        RoutineDefinition(
          id: 'meditazione',
          name: 'Meditazione',
          iconKey: 'meditation',
          position: 0,
        ),
      ],
    );

    final first = controller.toggleRoutine('meditazione');
    expect(controller.entryFor('meditazione').status, RoutineStatus.ok);
    expect(controller.entryFor('meditazione').completionTimeMinutes, 570);
    await Future<void>.delayed(Duration.zero);
    expect(repository.saves, hasLength(1));

    final second = controller.toggleRoutine('meditazione');
    expect(controller.entryFor('meditazione').status, RoutineStatus.ko);
    expect(repository.saves, hasLength(1));

    repository.saves.first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(repository.saves, hasLength(2));
    repository.saves.last.complete();
    await Future.wait([first, second]);
    expect(controller.isSaving, isFalse);
  });

  testWidgets('reloads silently when the mobile routine changes', (
    tester,
  ) async {
    final repository = _RealtimeRoutineRepository();
    final controller = RoutineController(
      repository: repository,
      initialDate: DateTime(2026, 8, 25),
      initialHistory: const [
        RoutineDefinition(
          id: 'meditazione',
          name: 'Meditazione',
          iconKey: 'meditation',
          position: 0,
        ),
      ],
    );
    await controller.load();
    controller.startAutoRefresh(pollingInterval: const Duration(hours: 1));

    repository.remoteEntry = const RoutineEntry(status: RoutineStatus.ok);
    repository.changes.add(null);
    await tester.pump(const Duration(milliseconds: 351));
    await tester.pump();

    expect(repository.fetches, 2);
    expect(controller.entryFor('meditazione').status, RoutineStatus.ok);
    expect(controller.isLoading, isFalse);

    controller.dispose();
    await repository.changes.close();
  });
}

class _FakeRoutineRepository implements RoutineRepository {
  final saves = <Completer<void>>[];

  @override
  Future<RoutineDayRemoteState> fetchDay(DateTime date) async =>
      const RoutineDayRemoteState(
        history: [],
        entries: {},
        effectiveScreenTimeMinutes: null,
      );

  @override
  Future<Map<DateTime, Map<String, RoutineEntry>>> fetchEntries({
    required DateTime start,
    required DateTime endExclusive,
  }) async => {};

  @override
  Future<void> saveDay({
    required DateTime date,
    required List<RoutineDefinition> history,
    required Map<String, RoutineEntry> entries,
  }) {
    final completer = Completer<void>();
    saves.add(completer);
    return completer.future;
  }
}

class _RealtimeRoutineRepository
    implements RoutineRepository, RoutineChangeFeed {
  final changes = StreamController<void>.broadcast();
  var remoteEntry = const RoutineEntry();
  var fetches = 0;
  bool failSave = false;
  Completer<RoutineDayRemoteState>? pending;

  @override
  Stream<void> watchChanges() => changes.stream;

  @override
  Future<RoutineDayRemoteState> fetchDay(DateTime date) async {
    fetches += 1;
    if (pending != null) return pending!.future;
    return RoutineDayRemoteState(
      history: const [],
      entries: {'meditazione': remoteEntry},
      effectiveScreenTimeMinutes: null,
    );
  }

  @override
  Future<Map<DateTime, Map<String, RoutineEntry>>> fetchEntries({
    required DateTime start,
    required DateTime endExclusive,
  }) async => {};

  @override
  Future<void> saveDay({
    required DateTime date,
    required List<RoutineDefinition> history,
    required Map<String, RoutineEntry> entries,
  }) async {
    if (failSave) throw StateError('offline');
    remoteEntry = entries['meditazione'] ?? const RoutineEntry();
  }
}
