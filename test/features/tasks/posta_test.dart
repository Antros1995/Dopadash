import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/core/storage/key_value_store.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/application/calendar_controller.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/data/calendar_repository.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/domain/calendar_event.dart';
import 'package:monitoraggio_personale_desktop/features/dashboard/presentation/widgets/home_components.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/application/posta_calendar_sync.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/application/task_controller.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/data/task_repository.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/domain/dashboard_task.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/presentation/todo_page.dart';

class _Store implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class _Tasks
    implements
        TaskRepository,
        IncrementalTaskRepository,
        CalendarPostaRepository {
  List<DashboardTask> values = [];
  int writes = 0;
  final events = StreamController<List<DashboardTask>>.broadcast(sync: true);
  bool emit = true;
  @override
  Future<List<DashboardTask>> load() async => List.of(values);
  @override
  Stream<List<DashboardTask>> watch() => events.stream;
  @override
  Future<void> save(List<DashboardTask> tasks) async {
    writes++;
    final merged = {
      for (final t in values) t.id: t,
      for (final t in tasks) t.id: t,
    };
    values = merged.values.toList();
    if (emit) events.add(List.of(values));
  }

  @override
  Future<void> saveUpdates(List<DashboardTask> tasks) => save(tasks);
  @override
  Future<void> delete(String id) async {
    writes++;
    values.removeWhere((t) => t.id == id);
    if (emit) events.add(List.of(values));
  }

  @override
  Future<List<DashboardTask>> importPosta(
    List<DashboardTask> tasks, {
    bool migrate = false,
  }) async {
    final result = <DashboardTask>[];
    for (final task in tasks) {
      final existing = values
          .where((t) => t.calendarEventId == task.calendarEventId)
          .firstOrNull;
      result.add(
        DashboardTask(
          id:
              existing?.id ??
              '00000000-0000-4000-8000-${(values.length + result.length + 1).toString().padLeft(12, '0')}',
          title: existing?.isDeleted == true ? existing!.title : task.title,
          group: DashboardTaskGroup.posta,
          color: existing?.color ?? task.color,
          scheduledDate: existing?.scheduledDate ?? task.scheduledDate,
          dueAt: existing?.isDeleted == true ? existing!.dueAt : task.dueAt,
          createdAt: existing?.createdAt ?? task.createdAt,
          completedAt: existing != null
              ? existing.completedAt
              : (migrate ? task.completedAt : null),
          calendarEventId: task.calendarEventId,
          deletedAt: existing?.deletedAt ?? (migrate ? task.deletedAt : null),
        ),
      );
    }
    await saveUpdates(result);
    return result;
  }
}

CalendarDay day(int date, {bool cancelled = false}) => CalendarDay(
  date: '2026-10-${date.toString().padLeft(2, '0')}',
  timeZone: 'Europe/Rome',
  events: [
    for (final hour in [17, 8])
      CalendarEvent(
        id: 'event-$date-$hour',
        subject: 'Ricordo $date ore $hour',
        startDateTime:
            '2026-10-${date.toString().padLeft(2, '0')}T${hour.toString().padLeft(2, '0')}:00:00',
        endDateTime: '2026-10-${date.toString().padLeft(2, '0')}T18:00:00',
        location: '',
        isAllDay: false,
        isCancelled: cancelled,
      ),
  ],
);

class _Calendar implements CalendarRepository {
  final requested = <int>[];
  bool fail = false;
  @override
  bool get isConfigured => true;
  @override
  Future<CalendarDay> fetchDay(DateTime date) async {
    requested.add(date.day);
    if (fail) throw const CalendarFailure(CalendarFailureKind.unavailable);
    return day(date.day);
  }

  @override
  Future<Uri> beginOutlookConnect() async => Uri.parse('https://example.com');
  @override
  void dispose() {}
}

void main() {
  test(
    'two devices synchronize Posta completion reopening and deletion immediately',
    () async {
      final remote = _Tasks();
      TaskController create() => TaskController(
        repository: remote,
        cacheStore: _Store(),
        now: () => DateTime(2026, 10, 13),
      );
      final pc = create(), phone = create();
      addTearDown(() {
        pc.dispose();
        phone.dispose();
      });
      await pc.load();
      await phone.load();
      await pc.importCalendarDay(day(12));
      expect(phone.overviewTasks.length, 2);
      final id = pc.overviewTasks.first.id;
      expect(id.startsWith('posta-calendar-'), isFalse);
      remote.emit =
          false; // Simulate a delayed realtime notification on the phone.
      await pc.toggle(id);
      expect(phone.overviewTasks.first.isCompleted, isFalse);
      final original = day(12);
      await phone.importCalendarDay(
        CalendarDay(
          date: original.date,
          timeZone: original.timeZone,
          events: [
            for (final e in original.events)
              CalendarEvent(
                id: e.id,
                subject: '${e.subject} aggiornato',
                startDateTime: e.startDateTime,
                endDateTime: e.endDateTime,
                location: '',
                isAllDay: false,
                isCancelled: false,
              ),
          ],
        ),
      );
      expect(
        phone.overviewTasks.firstWhere((t) => t.id == id).isCompleted,
        isTrue,
      );
      remote.emit = true;
      await phone.toggle(id);
      expect(
        pc.overviewTasks.firstWhere((t) => t.id == id).isCompleted,
        isFalse,
      );
      await pc.toggle(id);
      expect(
        phone.overviewTasks.firstWhere((t) => t.id == id).isCompleted,
        isTrue,
      );
      await phone.delete(id);
      expect(pc.overviewTasks.any((t) => t.id == id), isFalse);
      await pc.importCalendarDay(day(12));
      expect(remote.values.firstWhere((t) => t.id == id).isDeleted, isTrue);
      expect(pc.overviewTasks.any((t) => t.id == id), isFalse);
    },
  );

  test(
    'legacy Posta cache migrates local spunts and deletion tombstones to server',
    () async {
      final store = _Store(), remote = _Tasks();
      final event = day(12).events.last;
      final id = 'posta-calendar-${base64Url.encode(utf8.encode(event.id))}';
      final deletedId =
          'posta-calendar-${base64Url.encode(utf8.encode(day(12).events.first.id))}';
      final old = DashboardTask(
        id: id,
        title: event.subject,
        group: DashboardTaskGroup.posta,
        color: DashboardTaskColor.red,
        scheduledDate: DateTime(2026, 10, 12),
        dueAt: DateTime(2026, 10, 12, 8),
        createdAt: DateTime(2026, 10, 12),
        completedAt: DateTime(2026, 10, 12, 9),
      );
      await store.write(
        'dashboard.tasks.cache.v1.local',
        jsonEncode({
          'tasks': [old.toJson()],
          'postaDeletedIds': [deletedId],
          'pending': false,
        }),
      );
      final pc = TaskController(
        repository: remote,
        cacheStore: store,
        now: () => DateTime(2026, 10, 13),
      );
      final phone = TaskController(
        repository: remote,
        cacheStore: _Store(),
        now: () => DateTime(2026, 10, 13),
      );
      addTearDown(() {
        pc.dispose();
        phone.dispose();
      });
      await pc.load();
      await phone.load();
      expect(phone.overviewTasks.single.isCompleted, isTrue);
      expect(phone.overviewTasks.single.color, DashboardTaskColor.red);
      expect(phone.overviewTasks.single.id, isNot(id));
      await phone.importCalendarDay(day(12));
      expect(phone.overviewTasks.length, 1);
      expect(remote.values.where((t) => t.isDeleted).length, 1);
      await pc.flushPendingSaves();
      expect(
        jsonDecode(
          store.values['dashboard.tasks.cache.v1.local']!,
        )['postaCloudMigrated'],
        isTrue,
      );
    },
  );

  test(
    'Posta remote serialization preserves calendar identity deadline and deletion',
    () {
      final task = DashboardTask(
        id: '00000000-0000-4000-8000-000000000001',
        title: 'Promemoria',
        group: DashboardTaskGroup.posta,
        color: DashboardTaskColor.blue,
        scheduledDate: DateTime(2026, 10, 12),
        dueAt: DateTime(2026, 10, 12, 8),
        createdAt: DateTime.utc(2026, 10, 12),
        completedAt: DateTime.utc(2026, 10, 12, 9),
        calendarEventId: 'outlook-event',
        deletedAt: DateTime.utc(2026, 10, 13),
      );
      final remote = task.toRemoteJson('user');
      final restored = DashboardTask.fromRemoteJson({
        ...remote,
        'created_at': task.createdAt.toIso8601String(),
      });
      expect(restored.dueAt, task.dueAt);
      expect(restored.calendarEventId, task.calendarEventId);
      expect(restored.completedAt, task.completedAt);
      expect(restored.isDeleted, isTrue);
    },
  );

  test(
    'Posta excludes old events, orders deadlines, carries and restores completion',
    () async {
      final store = _Store(), remote = _Tasks();
      var now = DateTime(2026, 10, 12, 20);
      TaskController create() => TaskController(
        repository: remote,
        cacheStore: store,
        initialDate: now,
        now: () => now,
      );
      final tasks = create();
      await tasks.load();
      await tasks.importCalendarDay(day(11));
      await tasks.importCalendarDay(day(12, cancelled: true));
      expect(tasks.overviewTasks, isEmpty);
      await tasks.importCalendarDay(day(12));
      await tasks.importCalendarDay(day(12));
      expect(tasks.overviewTasks.length, 2);
      expect(
        tasks.tasksFor(DashboardTaskGroup.posta).map((t) => t.dueAt!.hour),
        [8, 17],
      );
      await tasks.toggle(tasks.overviewTasks.first.id);
      await tasks.importCalendarDay(day(12));
      await tasks.flushPendingSaves();
      tasks.dispose();
      now = DateTime(2026, 10, 13, 9);
      final restored = create();
      addTearDown(restored.dispose);
      await restored.load();
      final pending = restored.tasksFor(DashboardTaskGroup.posta).single;
      expect(pending.dueAt, DateTime(2026, 10, 12, 17));
      expect(restored.dateFor(pending), DateTime(2026, 10, 13));
      expect(restored.overviewTasks.where((t) => t.isCompleted).length, 1);
      expect(remote.values.where((t) => t.isCompleted).length, 1);
    },
  );

  test(
    'Posta deletes stay deleted on the server without changing other task groups',
    () async {
      final store = _Store(), remote = _Tasks();
      TaskController create() => TaskController(
        repository: remote,
        cacheStore: store,
        now: () => DateTime(2026, 10, 12),
      );
      final tasks = create();
      await tasks.load();
      await tasks.importCalendarDay(day(12));
      final id = tasks.overviewTasks.first.id;
      await tasks.delete(id);
      await tasks.flushPendingSaves();
      tasks.dispose();
      final restored = create();
      addTearDown(restored.dispose);
      await restored.load();
      await restored.importCalendarDay(day(12));
      expect(restored.overviewTasks.any((t) => t.id == id), isFalse);
      await restored.addTask(
        title: 'Posta manuale',
        group: DashboardTaskGroup.posta,
      );
      expect(remote.values.any((t) => t.title == 'Posta manuale'), isTrue);
      await restored.addTask(
        title: 'Personale',
        group: DashboardTaskGroup.personal,
      );
      expect(
        remote.values
            .where((t) => t.group == DashboardTaskGroup.personal)
            .single
            .title,
        'Personale',
      );
    },
  );

  test(
    'calendar catch-up starts on October 12 and retries without duplicate reminders',
    () async {
      final remote = _Tasks(), calendarRepo = _Calendar();
      final tasks = TaskController(
        repository: remote,
        cacheStore: _Store(),
        now: () => DateTime(2026, 10, 13),
      );
      final calendar = CalendarController(repository: calendarRepo);
      final sync = PostaCalendarSync(calendar: calendar, tasks: tasks);
      addTearDown(() {
        sync.dispose();
        calendar.dispose();
        tasks.dispose();
      });
      await tasks.load();
      calendarRepo.fail = true;
      await sync.sync();
      expect(tasks.postaSyncError, isNotNull);
      expect(tasks.postaSyncDate, isNull);
      calendarRepo.fail = false;
      await sync.sync();
      expect(calendarRepo.requested, [12, 12, 13]);
      expect(tasks.postaSyncDate, DateTime(2026, 10, 13));
      expect(tasks.postaSyncError, isNull);
      expect(tasks.overviewTasks.length, 4);
      await sync.sync();
      expect(tasks.overviewTasks.length, 4);
    },
  );

  testWidgets('Posta appears in To Do today and in the monitoring preview', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1354, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tasks = TaskController(
      repository: _Tasks(),
      cacheStore: _Store(),
      initialDate: DateTime(2026, 10, 13),
      now: () => DateTime(2026, 10, 13),
    );
    await tasks.load();
    await tasks.importCalendarDay(day(12));
    final key = GlobalKey<TodoPageState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: TodoPage(key: key, controller: tasks),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.showSection('Posta');
    await tester.pumpAndSettle();
    expect(find.text('Posta'), findsWidgets);
    expect(find.text('Ricordo 12 ore 8'), findsOneWidget);
    key.currentState!.showSection('Oggi');
    await tester.pumpAndSettle();
    expect(find.text('Ricordo 12 ore 8'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 260,
            child: HomeTaskPreview(
              title: 'Posta',
              group: DashboardTaskGroup.posta,
              controller: tasks,
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Posta'), findsOneWidget);
    expect(find.text('Ricordo 12 ore 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    tasks.dispose();
  });
}
