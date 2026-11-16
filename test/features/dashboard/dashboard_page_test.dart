import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/application/calendar_controller.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/data/calendar_repository.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/domain/calendar_event.dart';
import 'package:monitoraggio_personale_desktop/features/dashboard/presentation/dashboard_page.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/application/fitbit_controller.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/domain/fitbit_day.dart';
import 'package:monitoraggio_personale_desktop/features/dashboard/presentation/health_presentation.dart';
import 'package:monitoraggio_personale_desktop/features/dashboard/presentation/widgets/health_overview.dart';
import 'package:monitoraggio_personale_desktop/features/shell/presentation/dashboard_frame.dart';

import 'package:monitoraggio_personale_desktop/features/routines/application/routine_controller.dart';
import 'package:monitoraggio_personale_desktop/features/routines/data/routine_repository.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/application/task_controller.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/data/task_repository.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/domain/dashboard_task.dart';

void main() {
  testWidgets('hypnogram tolerates transient collapsed browser layout', (
    tester,
  ) async {
    final stage = FitbitSleepStage(
      startTime: DateTime(2026, 7, 22, 1),
      endTime: DateTime(2026, 7, 22, 2),
      type: 'DEEP',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 40,
            height: 24,
            child: SleepHypnogram(stages: [stage], details: null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(1920, 1080),
    const Size(1366, 768),
    const Size(1024, 768),
    const Size(390, 844),
  ]) {
    testWidgets('reference home and frame remain usable at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final routines = RoutineController(
        repository: _DashboardRepository(),
        initialDate: DateTime(2026, 8, 25),
      );
      final calendar = CalendarController(
        repository: _DashboardCalendarRepository(),
        initialDate: routines.selectedDate,
      );
      final fitbit = FitbitController(
        repository: _DashboardFitbitRepository(),
        initialDate: routines.selectedDate,
      );
      final tasks = TaskController(
        repository: _DashboardTaskRepository(),
        initialDate: routines.selectedDate,
      );
      addTearDown(routines.dispose);
      addTearDown(calendar.dispose);
      addTearDown(fitbit.dispose);
      addTearDown(tasks.dispose);
      await Future.wait([
        routines.load(),
        calendar.load(),
        fitbit.load(),
        tasks.load(),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: DashboardFrame(
            fitbit: fitbit,
            routines: routines,
            selectedPage: 0,
            section: 'Panoramica',
            onPage: (_) {},
            onSection: (_) {},
            onSearch: () {},
            onSettings: () {},
            onStatus: () {},
            child: DashboardPage(
              routines: routines,
              calendar: calendar,
              fitbit: fitbit,
              tasks: tasks,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Sonno'), findsWidgets);
      expect(
        find.byKey(const ValueKey('fitbit-sleep-timeline')),
        findsOneWidget,
      );
      expect(find.text('Stato del corpo'), findsOneWidget);
      expect(find.text('HRV'), findsOneWidget);
      expect(find.text('SpO₂'), findsNothing);
      expect(find.text('Mindfulness'), findsNothing);
      expect(find.textContaining('biologica'), findsNothing);
      if (size.width >= 1366) {
        final sleep = tester.getTopLeft(
          find.byKey(const ValueKey('fitbit-sleep-timeline')),
        );
        final routine = tester.getTopLeft(find.text('Routine del giorno'));
        final health = tester.getTopLeft(
          find.text('I tuoi parametri di salute'),
        );
        expect(sleep.dy, lessThan(health.dy));
        expect(health.dy, lessThan(routine.dy));
        expect(routine.dy, lessThan(size.height));
      }
      if (size.width >= 1366) {
        await tester.tap(find.text('Dettagli ›'));
        await tester.pumpAndSettle();
        expect(find.text('Intervalli registrati'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Chiudi'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Vedi tutte ›').first);
      await tester.tap(find.text('Vedi tutte ›').first);
      await tester.pumpAndSettle();
      expect(find.text('Le tue routine'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Meditazione'),
        ),
      );
      await tester.pumpAndSettle();
      expect(routines.entryFor('meditazione').isCompleted, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('date navigation keeps all four controllers aligned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final routines = RoutineController(
      repository: _DashboardRepository(),
      initialDate: DateTime(2026, 8, 25),
    );
    final calendar = CalendarController(
      repository: _DashboardCalendarRepository(),
      initialDate: routines.selectedDate,
    );
    final fitbit = FitbitController(
      repository: _DashboardFitbitRepository(),
      initialDate: routines.selectedDate,
    );
    final tasks = TaskController(
      repository: _DashboardTaskRepository(),
      initialDate: routines.selectedDate,
    );
    addTearDown(routines.dispose);
    addTearDown(calendar.dispose);
    addTearDown(fitbit.dispose);
    addTearDown(tasks.dispose);
    await Future.wait([
      routines.load(),
      calendar.load(),
      fitbit.load(),
      tasks.load(),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: DashboardPage(
            routines: routines,
            calendar: calendar,
            fitbit: fitbit,
            tasks: tasks,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Giorno precedente'));
    await tester.pumpAndSettle();
    for (final selected in [
      routines.selectedDate,
      calendar.selectedDate,
      fitbit.selectedDate,
      tasks.selectedDate,
    ]) {
      expect(selected, DateTime(2026, 8, 24));
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'empty health measurements collapse without placeholder metrics',
    (tester) async {
      final fitbit = FitbitController(repository: _EmptyFitbitRepository());
      addTearDown(fitbit.dispose);
      await fitbit.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthOverview(controller: fitbit, isToday: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'HRV',
        'FC a riposo',
        'SpO₂',
        'Passi',
        'Calorie',
        'Mindfulness',
        'VO₂ max',
        'Zone attive',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(
        find.text('Nessun parametro valido per questa giornata.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fitbit-sleep-timeline')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'heart rate measurement and interval average have distinct labels',
    (tester) async {
      final sample = FitbitHeartSample(
        measuredAt: DateTime(2026, 8, 25, 14, 17),
        beatsPerMinute: 85,
      );
      final exact = FitbitController(
        repository: _DashboardFitbitRepository(latestHeartRate: sample),
      );
      final aggregate = FitbitController(
        repository: _DashboardFitbitRepository(),
      );
      addTearDown(exact.dispose);
      addTearDown(aggregate.dispose);
      await Future.wait([exact.load(), aggregate.load()]);

      Future<void> show(FitbitController fitbit, {required bool isToday}) =>
          tester.pumpWidget(
            MaterialApp(
              theme: buildDesktopTheme(),
              home: Scaffold(
                body: HealthOverview(
                  controller: fitbit,
                  isToday: isToday,
                  panel: 'metrics',
                ),
              ),
            ),
          );

      await show(exact, isToday: true);
      expect(find.text('Ultimo battito'), findsOneWidget);
      expect(find.text('Misurato alle 14:17'), findsOneWidget);
      expect(find.text('FC media'), findsNothing);

      await show(aggregate, isToday: true);
      expect(find.text('Ultimo battito'), findsNothing);
      expect(find.text('FC media'), findsOneWidget);
      expect(find.text('14:00–14:30'), findsOneWidget);

      await show(exact, isToday: false);
      expect(find.text('Ultimo battito'), findsNothing);
      expect(find.text('FC media'), findsNothing);
      expect(find.text('FC a riposo'), findsOneWidget);
    },
  );
  test(
    'historical undated trends cannot produce recovery or baseline claims',
    () async {
      final day = (await _DashboardFitbitRepository().fetchDay(
        DateTime(2026, 8, 25),
      )).day!;
      final historical = HealthPresentation(day, isToday: false);
      expect(historical.recovery, isNull);
      expect(historical.insights.any((s) => s.contains('media')), isFalse);
      expect(HealthPresentation(day, isToday: true).recovery, isNotNull);
      final missing = HealthPresentation(_emptyDay, isToday: true);
      expect(missing.sleepScore, isNull);
      expect(missing.recovery, isNull);
      expect(missing.load, isNull);
      expect(missing.insights, isEmpty);
    },
  );
}

final _emptyDay = FitbitDay(
  date: '2026-08-25',
  finalized: true,
  syncedAt: DateTime(2026, 8, 25),
  steps: 0,
  distanceKm: 0,
  calories: 0,
  activeMinutes: 0,
  restingHeartRate: null,
  sleepMinutes: null,
  sleepEfficiency: null,
);

class _EmptyFitbitRepository extends _DashboardFitbitRepository {
  @override
  Future<FitbitStatus> fetchDay(DateTime date) async => FitbitStatus(
    configured: true,
    connection: 'CONNECTED',
    deviceName: 'Charge 6',
    day: _emptyDay,
  );
}

class _DashboardTaskRepository implements TaskRepository {
  List<DashboardTask> values = [];

  @override
  Future<List<DashboardTask>> load() async => List.of(values);

  @override
  Stream<List<DashboardTask>> watch() => const Stream.empty();

  @override
  Future<void> save(List<DashboardTask> tasks) async {
    values = List.of(tasks);
  }

  @override
  Future<void> delete(String id) async {
    values.removeWhere((task) => task.id == id);
  }
}

class _DashboardFitbitRepository implements FitbitRepository {
  _DashboardFitbitRepository({this.latestHeartRate});

  final FitbitHeartSample? latestHeartRate;

  @override
  bool get isConfigured => true;

  @override
  Future<Uri> beginConnect() async =>
      Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');

  @override
  Future<FitbitStatus> fetchDay(DateTime date) async => FitbitStatus(
    configured: true,
    connection: 'CONNECTED',
    deviceName: 'Charge 6',
    day: FitbitDay(
      date: '2026-08-25',
      finalized: true,
      syncedAt: DateTime.utc(2026, 8, 26),
      steps: 8432,
      distanceKm: 6.1,
      calories: 2140,
      activeMinutes: 48,
      activeZoneMinutesByZone: const FitbitActiveZoneMinutes(
        fatBurn: 32,
        cardio: 18,
        peak: 4,
      ),
      restingHeartRate: 58,
      latestHeartRate: latestHeartRate,
      sleepMinutes: 441,
      sleepEfficiency: 91,
      heartRateVariabilityMs: 48,
      heartRateVariabilityTrend: const [42, 44, 45, 43, 46],
      restingHeartRateTrend: const [60, 59, 58, 60, 57],
      heartProfile: [
        FitbitHeartPoint(
          startTime: DateTime(2026, 8, 25, 14),
          average: 72,
          minimum: 70,
          maximum: 85,
        ),
      ],
      sleepDetails: FitbitSleepDetails(
        startTime: DateTime.utc(2026, 8, 24, 22, 10),
        endTime: DateTime.utc(2026, 8, 25, 4, 58),
        type: 'STAGES',
        processed: true,
        stagesStatus: 'SUCCEEDED',
        minutesInSleepPeriod: 408,
        minutesAwake: 15,
        minutesToFallAsleep: 4,
        minutesAfterWakeUp: 0,
        stageMinutes: const FitbitSleepStageMinutes(
          awake: 15,
          light: 210,
          deep: 88,
          rem: 95,
          asleep: 0,
          restless: 0,
        ),
        shortAwakenings: const [],
      ),
      sleepStages: [
        FitbitSleepStage(
          startTime: DateTime.utc(2026, 8, 24, 22, 10),
          endTime: DateTime.utc(2026, 8, 24, 23, 20),
          type: 'LIGHT',
        ),
        FitbitSleepStage(
          startTime: DateTime.utc(2026, 8, 25, 4, 58),
          endTime: DateTime.utc(2026, 8, 25, 4, 58),
          type: 'AWAKE',
        ),
      ],
    ),
  );

  @override
  Future<FitbitStatus> saveMindfulnessMinutes(DateTime date, int? minutes) =>
      fetchDay(date);

  @override
  void dispose() {}
}

class _DashboardCalendarRepository implements CalendarRepository {
  @override
  bool get isConfigured => true;

  @override
  Future<Uri> beginOutlookConnect() async =>
      Uri.parse('https://login.microsoftonline.com/authorize');

  @override
  Future<CalendarDay> fetchDay(DateTime date) async => CalendarDay(
    date: '2026-08-25',
    timeZone: 'Europe/Rome',
    events: const [
      CalendarEvent(
        id: 'event-1',
        subject: 'Riunione progetto',
        startDateTime: '2026-08-25T09:00:00',
        endDateTime: '2026-08-25T10:00:00',
        location: 'Online',
        isAllDay: false,
        isCancelled: false,
      ),
    ],
  );

  @override
  void dispose() {}
}

class _DashboardRepository implements RoutineRepository {
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
  }) async {}
}
