// DopaDash demo: the real app widgets filled with generated, fictional data.
// No account, Supabase project or Fitbit needed. Every number, task and event
// below is invented. Never imported by lib/main.dart.
//
//   flutter run -d chrome -t tool/demo_app.dart
//
// Add ?page=N to the URL to open a section directly:
// 0 Monitoraggio, 1 To Do, 6 Statistiche, 8 Quotidianità, 9 Sport.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/application/calendar_controller.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/data/calendar_repository.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/domain/calendar_event.dart';
import 'package:monitoraggio_personale_desktop/features/daily/application/daily_controller.dart';
import 'package:monitoraggio_personale_desktop/features/daily/data/daily_repository.dart';
import 'package:monitoraggio_personale_desktop/features/daily/domain/daily_models.dart';
import 'package:monitoraggio_personale_desktop/features/daily/presentation/daily_page.dart';
import 'package:monitoraggio_personale_desktop/features/daily/presentation/recap_view.dart';
import 'package:monitoraggio_personale_desktop/features/daily/presentation/sport_page.dart';
import 'package:monitoraggio_personale_desktop/features/dashboard/presentation/dashboard_page.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/application/fitbit_controller.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/domain/fitbit_day.dart';
import 'package:monitoraggio_personale_desktop/features/routines/application/routine_controller.dart';
import 'package:monitoraggio_personale_desktop/features/routines/data/routine_repository.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine.dart';
import 'package:monitoraggio_personale_desktop/features/shell/presentation/dashboard_frame.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/application/task_controller.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/data/task_repository.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/domain/dashboard_task.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/presentation/todo_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final today = dateOnly(DateTime.now());
  final fitbit = FitbitController(
    repository: _DemoFitbit(today),
    initialDate: today,
  );
  final routines = RoutineController(
    repository: _DemoRoutines(),
    initialDate: today,
  );
  final calendar = CalendarController(
    repository: _DemoCalendar(),
    initialDate: today,
  );
  final tasks = TaskController(
    repository: _DemoTasks(today),
    initialDate: today,
  );
  await Future.wait([
    fitbit.load(),
    routines.load(),
    calendar.load(),
    tasks.load(),
  ]);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DopaDash demo',
      theme: buildDesktopTheme(),
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _Demo(fitbit, routines, calendar, tasks),
    ),
  );
}

class _Demo extends StatefulWidget {
  const _Demo(this.fitbit, this.routines, this.calendar, this.tasks);
  final FitbitController fitbit;
  final RoutineController routines;
  final CalendarController calendar;
  final TaskController tasks;
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  static const _pages = [0, 1, 6, 8, 9];
  final dashboardKey = GlobalKey<DashboardPageState>();
  final todoKey = GlobalKey<TodoPageState>();
  final dailyKey = GlobalKey<DailyPageState>();
  final sportKey = GlobalKey<SportPageState>();
  String section = 'Panoramica';
  late int selected = () {
    final page = int.tryParse(Uri.base.queryParameters['page'] ?? '') ?? 0;
    return _pages.contains(page) ? page : 0;
  }();
  late final daily = DailyController(
    repository: _DemoDaily(),
    initialDate: widget.routines.selectedDate,
    onScreenTimeChanged: widget.routines.refreshSilently,
  );

  void selectDay(DateTime date) {
    widget.routines.selectDate(date);
    daily.selectDate(date);
    widget.fitbit.selectDate(date);
  }

  @override
  void initState() {
    super.initState();
    daily.start();
    // ?section=Name opens a section of the chosen page, e.g. ?page=6&section=Sonno
    final wanted = Uri.base.queryParameters['section'];
    if (wanted != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showSection(wanted));
    }
  }

  void showSection(String s) {
    setState(() => section = s);
    switch (selected) {
      case 0:
        dashboardKey.currentState?.showSection(s);
      case 1:
        todoKey.currentState?.showSection(s);
      case 8:
        dailyKey.currentState?.showSection(s);
      case 9:
        sportKey.currentState?.showSection(s);
    }
  }

  @override
  void dispose() {
    daily.dispose();
    super.dispose();
  }

  void info() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Demo DopaDash'),
      content: const Text(
        'Questa è una demo con dati inventati. Nella demo sono disponibili '
        'Monitoraggio, To Do, Statistiche, Quotidianità e Sport. Per usare '
        'tutte le sezioni con i tuoi dati, segui il README.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => DashboardFrame(
    fitbit: widget.fitbit,
    routines: widget.routines,
    selectedPage: selected,
    section: section,
    onPage: (index) {
      if (_pages.contains(index)) {
        setState(() {
          selected = index;
          section = 'Panoramica';
        });
      } else {
        info();
      }
    },
    onSection: showSection,
    onSearch: info,
    onStatus: info,
    onSettings: info,
    child: IndexedStack(
      index: _pages.indexOf(selected),
      children: [
        DashboardPage(
          key: dashboardKey,
          routines: widget.routines,
          calendar: widget.calendar,
          fitbit: widget.fitbit,
          tasks: widget.tasks,
          scope: 'demo',
          onMarkets: info,
        ),
        TodoPage(key: todoKey, controller: widget.tasks, scope: 'demo'),
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final name in const ['Abitudini', 'Cellulare', 'Sport']) ...[
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                RecapView(
                  section: name,
                  routines: widget.routines,
                  repository: daily.repository,
                  today: widget.routines.selectedDate,
                ),
                const SizedBox(height: 28),
              ],
            ],
          ),
        ),
        DailyPage(
          key: dailyKey,
          routines: widget.routines,
          daily: daily,
          onSelectDate: selectDay,
        ),
        SportPage(
          key: sportKey,
          routines: widget.routines,
          daily: daily,
          fitbit: widget.fitbit,
          onSelectDate: selectDay,
        ),
      ],
    ),
  );
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Generated Fitbit days: plausible, slowly improving, and entirely fictional.
class _DemoFitbit implements FitbitRepository {
  _DemoFitbit(this.today);
  final DateTime today;
  final _cache = <String, FitbitDay>{};

  @override
  bool get isConfigured => true;

  @override
  Future<FitbitStatus> fetchDay(DateTime date) async {
    final day = dateOnly(date);
    final inRange = !day.isAfter(today) && today.difference(day).inDays < 180;
    return FitbitStatus(
      configured: true,
      connection: 'CONNECTED',
      deviceName: 'Fitbit Charge 6',
      day: inRange ? _cache.putIfAbsent(_key(day), () => _day(day)) : null,
    );
  }

  FitbitDay _day(DateTime day) {
    final age = today.difference(day).inDays;
    final random = Random(day.year * 1000 + day.month * 40 + day.day);
    final isToday = age == 0;
    final weekend = day.weekday >= DateTime.saturday;
    final gym =
        day.weekday == DateTime.monday ||
        day.weekday == DateTime.wednesday ||
        day.weekday == DateTime.friday;
    final run = day.weekday == DateTime.saturday;
    // Today stops at 18:45; earlier days are complete.
    final progress = isToday ? .78 : 1.0;
    double noise(double spread) => (random.nextDouble() * 2 - 1) * spread;

    final steps =
        ((weekend ? 10400 : 8300) + (run ? 3200 : 0) + noise(1900)) * progress;
    final restingHr = (62 - (180 - age) / 180 * 4 + noise(1.6)).round();
    final sleepMinutes = (432 + noise(42) + (weekend ? 25 : 0)).round();
    final bedtime = DateTime(
      day.year,
      day.month,
      day.day,
    ).subtract(Duration(minutes: 30 + random.nextInt(50)));
    final stages = _sleepStages(bedtime, sleepMinutes, random);
    int stageTotal(String type) => stages
        .where((s) => s['type'] == type)
        .fold(0, (sum, s) => sum + (s['minutes']! as int));
    final awake = stageTotal('awake');
    final wake = bedtime.add(Duration(minutes: sleepMinutes + awake));

    final workouts = <Map<String, Object?>>[
      if (gym && !isToday || gym && isToday && progress > .75)
        {
          'type': 'WEIGHTS',
          'name': 'Allenamento con i pesi',
          'startTime': DateTime(
            day.year,
            day.month,
            day.day,
            18,
            0,
          ).toIso8601String(),
          'activeMinutes': 48 + random.nextInt(15),
          'calories': 320 + random.nextInt(90),
          'distanceKm': null,
          'averageHeartRate': 118 + random.nextInt(14),
        },
      if (run)
        {
          'type': 'RUNNING',
          'name': 'Corsa',
          'startTime': DateTime(
            day.year,
            day.month,
            day.day,
            9,
            15,
          ).toIso8601String(),
          'activeMinutes': 34 + random.nextInt(12),
          'calories': 380 + random.nextInt(80),
          'distanceKm': 5.2 + random.nextDouble() * 1.6,
          'averageHeartRate': 146 + random.nextInt(10),
        },
    ];

    final heartProfile = <Map<String, Object?>>[];
    final end = isToday
        ? DateTime(day.year, day.month, day.day, 18, 45)
        : DateTime(day.year, day.month, day.day, 23, 45);
    for (
      var t = DateTime(day.year, day.month, day.day);
      !t.isAfter(end);
      t = t.add(const Duration(minutes: 15))
    ) {
      final hour = t.hour + t.minute / 60;
      final asleep = hour < wake.hour + wake.minute / 60;
      final training = workouts.any((w) {
        final start = DateTime.parse(w['startTime']! as String);
        final minutes = w['activeMinutes']! as int;
        return !t.isBefore(start) &&
            t.isBefore(start.add(Duration(minutes: minutes)));
      });
      final base = asleep
          ? restingHr - 4 + noise(3)
          : training
          ? 128 + noise(18)
          : 72 + 10 * sin(hour / 24 * pi) + noise(9);
      heartProfile.add({
        'startTime': t.toIso8601String(),
        'average': base,
        'minimum': base - 4 - random.nextInt(4),
        'maximum': base + 5 + random.nextInt(9),
      });
    }

    List<double> trend(double Function(DateTime d) value) => [
      for (var i = 6; i >= 0; i--)
        value(DateTime(day.year, day.month, day.day - i)),
    ];
    double stepsOn(DateTime d) {
      final r = Random(d.year * 1000 + d.month * 40 + d.day);
      final we = d.weekday >= DateTime.saturday;
      return (we ? 10400 : 8300) +
          (d.weekday == DateTime.saturday ? 3200 : 0) +
          (r.nextDouble() * 2 - 1) * 1900;
    }

    final zones = {
      'fatBurn': 18 + random.nextInt(25),
      'cardio': workouts.isEmpty ? random.nextInt(6) : 14 + random.nextInt(14),
      'peak': run ? 4 + random.nextInt(6) : random.nextInt(2),
    };
    final azm = zones['fatBurn']! + zones['cardio']! * 2 + zones['peak']! * 2;
    final hrv = 41 + (180 - age) / 180 * 6 + noise(5);

    return FitbitDay.fromJson({
      'date': _key(day),
      'finalized': !isToday,
      'syncedAt': isToday
          ? DateTime(day.year, day.month, day.day, 18, 42).toIso8601String()
          : DateTime(day.year, day.month, day.day, 23, 58).toIso8601String(),
      'steps': steps.round(),
      'distanceKm': steps * .00074,
      'calories': (2050 + steps * .045 + noise(120)).round(),
      'activeMinutes': (28 + (workouts.isEmpty ? 0 : 35) + noise(12)).round(),
      'sedentaryMinutes': (560 + noise(80) * progress).round(),
      'mindfulnessMinutes': random.nextInt(3) == 0 ? null : 10,
      'activeZoneMinutes': azm,
      'activeZoneMinutesByZone': zones,
      'restingHeartRate': restingHr,
      'latestHeartRate': {
        'measuredAt': end.toIso8601String(),
        'beatsPerMinute': 74 + random.nextInt(8),
      },
      'sleepMinutes': sleepMinutes,
      'sleepEfficiency': (sleepMinutes / (sleepMinutes + awake) * 100).round(),
      'sleepDetails': {
        'startTime': bedtime.toIso8601String(),
        'endTime': wake.toIso8601String(),
        'type': 'STAGES',
        'processed': true,
        'stagesStatus': 'SUCCEEDED',
        'minutesInSleepPeriod': sleepMinutes + awake,
        'minutesAwake': awake,
        'minutesToFallAsleep': 8 + random.nextInt(12),
        'minutesAfterWakeUp': 2 + random.nextInt(6),
        'stageMinutes': {
          'awake': awake,
          'light': stageTotal('light'),
          'deep': stageTotal('deep'),
          'rem': stageTotal('rem'),
        },
        'shortAwakenings': const [],
      },
      'oxygenSaturation': {
        'average': 96.4 + random.nextDouble() * 1.4,
        'minimum': 92.5 + random.nextDouble() * 2,
        'maximum': 99.0,
      },
      'heartRateVariabilityMs': hrv,
      'respiratoryRate': 14.2 + random.nextDouble() * 1.6,
      'skinTemperature': {
        'nightlyCelsius': 34.1 + noise(.4),
        'baselineCelsius': 34.1,
      },
      'vo2Max': {
        'value': 43.5 + (180 - age) / 180 * 1.5,
        'measuredDate': _key(day),
        'cardioFitnessLevel': 'GOOD',
        'estimated': true,
      },
      'workouts': workouts,
      'heartProfile': heartProfile,
      'sleepStages': [
        for (final s in stages)
          {
            'startTime': (s['start']! as DateTime).toIso8601String(),
            'endTime': (s['start']! as DateTime)
                .add(Duration(minutes: s['minutes']! as int))
                .toIso8601String(),
            'type': s['type'],
          },
      ],
      'trends': {
        'steps': trend(stepsOn),
        'restingHeartRate': trend(
          (d) => 62 - (180 - today.difference(d).inDays) / 180 * 4,
        ),
        'sleepMinutes': trend((d) => 432 + (d.day * 37 % 60) - 30),
        'heartRateVariabilityMs': trend(
          (d) => 41 + (180 - today.difference(d).inDays) / 180 * 6,
        ),
      },
    });
  }

  /// Roughly four or five sleep cycles: more deep sleep early, more REM late.
  List<Map<String, Object>> _sleepStages(
    DateTime start,
    int sleepMinutes,
    Random random,
  ) {
    final stages = <Map<String, Object>>[];
    var at = start;
    var slept = 0;
    var cycle = 0;
    void add(String type, int minutes) {
      if (minutes <= 0) return;
      stages.add({'type': type, 'start': at, 'minutes': minutes});
      at = at.add(Duration(minutes: minutes));
      if (type != 'awake') slept += minutes;
    }

    while (slept < sleepMinutes) {
      final left = sleepMinutes - slept;
      add('light', min(left, 22 + random.nextInt(14)));
      add(
        'deep',
        min(sleepMinutes - slept, max(4, 32 - cycle * 7 + random.nextInt(8))),
      );
      add('light', min(sleepMinutes - slept, 12 + random.nextInt(10)));
      add('rem', min(sleepMinutes - slept, 10 + cycle * 7 + random.nextInt(8)));
      if (random.nextInt(3) > 0) add('awake', 4 + random.nextInt(9));
      cycle++;
    }
    return stages;
  }

  @override
  Future<Uri> beginConnect() async => throw StateError('Demo');
  @override
  Future<FitbitStatus> saveMindfulnessMinutes(
    DateTime date,
    int? minutes,
  ) async => fetchDay(date);
  @override
  void dispose() {}
}

/// Default habits with a generated, fairly consistent history.
class _DemoRoutines implements RoutineRepository {
  List<RoutineDefinition> history = buildDefaultRoutineHistory();
  final days = <String, Map<String, RoutineEntry>>{};

  @override
  Future<RoutineDayRemoteState> fetchDay(DateTime date) async {
    final entries = days.putIfAbsent(
      formatDate(date),
      () => {
        'meditazione': const RoutineEntry(
          status: RoutineStatus.ok,
          completionTimeMinutes: 7 * 60 + 40,
        ),
        'camminata': const RoutineEntry(
          status: RoutineStatus.ok,
          completionTimeMinutes: 13 * 60 + 10,
        ),
        'studio': const RoutineEntry(
          status: RoutineStatus.ok,
          completionTimeMinutes: 16 * 60 + 30,
        ),
        'palestra': const RoutineEntry(
          status: RoutineStatus.ok,
          completionTimeMinutes: 18 * 60 + 45,
          selectedDetailOptionId: 'palestra_forza',
        ),
      },
    );
    return RoutineDayRemoteState(
      history: history,
      entries: entries,
      effectiveScreenTimeMinutes: 135,
    );
  }

  @override
  Future<Map<DateTime, Map<String, RoutineEntry>>> fetchEntries({
    required DateTime start,
    required DateTime endExclusive,
  }) async => {
    for (var d = dateOnly(start); d.isBefore(endExclusive); d = _nextDay(d))
      if (d.day % 11 != 0)
        d: {
          for (final r in history.where((r) => r.isValidOn(d)))
            r.id: RoutineEntry(
              // Each habit has its own success rate, so the bars differ.
              status:
                  Random(
                        d.year * 1000 + d.month * 40 + d.day + r.position * 7,
                      ).nextInt(10) <
                      const [1, 3, 2, 3, 4, 5, 1][r.position % 7]
                  ? RoutineStatus.ko
                  : RoutineStatus.ok,
              selectedDetailOptionId: r.id == 'palestra'
                  ? defaultGymOptions[d.day % defaultGymOptions.length].id
                  : null,
            ),
        },
  };

  @override
  Future<void> saveDay({
    required DateTime date,
    required List<RoutineDefinition> history,
    required Map<String, RoutineEntry> entries,
  }) async {
    this.history = history;
    days[formatDate(date)] = Map.of(entries);
  }
}

/// Mood check-ins, screen time and body measurements kept in memory.
class _DemoDaily implements DailyRepository {
  final emotions = <String, List<EmotionEntry>>{};
  final concentration = <String, List<ConcentrationEntry>>{};
  final movement = <String, int>{};
  final screen = <String, ScreenTime?>{};
  int _id = 0;
  late final measurements = <BodyMeasurement>[
    for (var i = 0; i < 9; i++)
      BodyMeasurement(
        date: _daysAgo((8 - i) * 15),
        values: {
          BodyMetric.weight: 78.4 - i * .45 + (i % 3) * .3,
          if (i.isEven) BodyMetric.waist: 88 - i * .5,
          if (i.isEven) BodyMetric.chest: 99 + i * .2,
          if (i % 4 == 0) BodyMetric.arms: 33 + i * .15,
          if (i % 4 == 0) BodyMetric.thigh: 55 + i * .1,
        },
      ),
  ];

  @override
  Future<DailyLifeDay> fetchDay(DateTime date) async {
    final k = formatDate(date);
    final at = DateTime(date.year, date.month, date.day, 9, 20);
    return DailyLifeDay(
      emotions: emotions.putIfAbsent(
        k,
        () => [
          EmotionEntry(
            id: 'e0',
            emotion: DailyEmotion.calm,
            intensity: 3,
            energy: DailyEnergy.medium,
            recordedAt: at,
          ),
        ],
      ),
      dayConcentration: concentration['d$k'] ?? const [],
      meditationConcentration: concentration['m$k'] ?? const [],
      movement: movement[k],
      screenTime: screen.containsKey(k)
          ? screen[k]
          : const ScreenTime(
              totalMinutes: 210,
              exclusions: [
                ScreenTimeExclusion(id: 'x', name: 'Mappe', minutes: 40),
                ScreenTimeExclusion(id: 'y', name: 'Lingue', minutes: 35),
              ],
            ),
    );
  }

  @override
  Future<void> addEmotion({
    required DateTime date,
    required DailyEmotion emotion,
    required int intensity,
    required DailyEnergy energy,
    int? concentration,
  }) async => emotions
      .putIfAbsent(formatDate(date), () => [])
      .add(
        EmotionEntry(
          id: 'e${++_id}',
          emotion: emotion,
          intensity: intensity,
          energy: energy,
          concentration: concentration,
          recordedAt: DateTime(date.year, date.month, date.day, 15, _id % 60),
        ),
      );

  @override
  Future<void> deleteEmotion(String id) async {
    for (final list in emotions.values) {
      list.removeWhere((e) => e.id == id);
    }
  }

  String _c(ConcentrationKind kind, DateTime date) =>
      '${kind == ConcentrationKind.day ? 'd' : 'm'}${formatDate(date)}';

  @override
  Future<void> addConcentration(
    ConcentrationKind kind,
    DateTime date,
    int level,
  ) async => concentration
      .putIfAbsent(_c(kind, date), () => [])
      .add(
        ConcentrationEntry(
          id: 'c${++_id}',
          level: level,
          recordedAt: DateTime(date.year, date.month, date.day, 15, _id % 60),
        ),
      );

  @override
  Future<void> deleteConcentration(ConcentrationKind kind, String id) async {
    for (final list in concentration.values) {
      list.removeWhere((e) => e.id == id);
    }
  }

  @override
  Future<void> saveMovement(DateTime date, int level) async =>
      movement[formatDate(date)] = level;
  @override
  Future<void> saveScreenTime(DateTime usageDate, ScreenTime? value) async =>
      screen[formatDate(usageDate.add(const Duration(days: 1)))] = value;
  @override
  Future<List<BodyMeasurement>> loadMeasurements() async =>
      measurements..sort((a, b) => a.date.compareTo(b.date));
  @override
  Future<void> saveMeasurement(BodyMeasurement measurement) async {
    measurements.removeWhere((m) => m.date == measurement.date);
    measurements.add(measurement);
  }

  @override
  Future<void> deleteMeasurement(DateTime date) async =>
      measurements.removeWhere((m) => m.date == date);
  @override
  Stream<void> watchChanges() => const Stream.empty();
  @override
  Future<Map<DateTime, int>> fetchScreenTimes(
    DateTime start,
    DateTime end,
  ) async => {
    for (var d = start; !d.isAfter(end); d = _nextDay(d))
      if (d.day % 6 != 0) d: 70 + (d.day * 37 + d.month * 11) % 170,
  };
  @override
  Future<Map<DateTime, int>> fetchMovements(
    DateTime start,
    DateTime end,
  ) async => {
    for (var d = start; !d.isAfter(end); d = _nextDay(d))
      if (d.day % 3 != 0) d: 1 + (d.day * 7) % 5,
  };
}

class _DemoCalendar implements CalendarRepository {
  @override
  bool get isConfigured => true;

  @override
  Future<CalendarDay> fetchDay(DateTime date) async {
    String at(int h, int m) =>
        DateTime(date.year, date.month, date.day, h, m).toIso8601String();
    CalendarEvent event(
      String id,
      String subject,
      int h,
      int m,
      int minutes, [
      String where = '',
    ]) => CalendarEvent.fromJson({
      'id': id,
      'subject': subject,
      'start': {'dateTime': at(h, m), 'timeZone': 'Europe/Rome'},
      'end': {
        'dateTime': at(h + (m + minutes) ~/ 60, (m + minutes) % 60),
        'timeZone': 'Europe/Rome',
      },
      'location': where,
      'isAllDay': false,
      'isCancelled': false,
    });
    return CalendarDay(
      date: date.toIso8601String().substring(0, 10),
      timeZone: 'Europe/Rome',
      events: [
        event('1', 'Stand-up del team', 9, 30, 15, 'Online'),
        event(
          '2',
          'Lavoro concentrato (telefono in un\'altra stanza)',
          10,
          0,
          90,
        ),
        event('3', 'Pausa camminata', 12, 30, 20),
        event('4', 'Revisione del progetto', 15, 0, 45, 'Sala riunioni'),
        event('5', 'Lezione di yoga', 19, 30, 60, 'Palestra'),
      ],
    );
  }

  @override
  Future<Uri> beginOutlookConnect() async => throw StateError('Demo');
  @override
  void dispose() {}
}

class _DemoTasks implements TaskRepository {
  _DemoTasks(this.day);
  final DateTime day;
  late List<DashboardTask> items = [
    task(
      '1',
      'Prenotare il dentista',
      DashboardTaskGroup.personal,
      DashboardTaskColor.red,
      0,
    ),
    task(
      '2',
      'Rinnovare l\'abbonamento della palestra',
      DashboardTaskGroup.personal,
      DashboardTaskColor.blue,
      3,
    ),
    task(
      '3',
      'Comprare un regalo di compleanno',
      DashboardTaskGroup.personal,
      DashboardTaskColor.black,
      -2,
    ),
    task(
      '4',
      'Annaffiare le piante',
      DashboardTaskGroup.personal,
      DashboardTaskColor.green,
      0,
      done: true,
    ),
    task(
      '5',
      'Preparare la presentazione di venerdì',
      DashboardTaskGroup.work,
      DashboardTaskColor.red,
      0,
    ),
    task(
      '6',
      'Rispondere alle email arretrate',
      DashboardTaskGroup.work,
      DashboardTaskColor.yellow,
      1,
    ),
    task(
      '7',
      'Aggiornare il foglio del budget',
      DashboardTaskGroup.work,
      DashboardTaskColor.green,
      5,
    ),
    task(
      '8',
      'Inviare il resoconto della riunione',
      DashboardTaskGroup.work,
      DashboardTaskColor.black,
      -1,
      done: true,
    ),
    task(
      '9',
      'Leggere un capitolo sul focus',
      DashboardTaskGroup.personalWork,
      DashboardTaskColor.blue,
      2,
    ),
    task(
      '10',
      'Aggiornare il curriculum',
      DashboardTaskGroup.personalWork,
      DashboardTaskColor.black,
      7,
    ),
    task(
      '11',
      'Bolletta da pagare',
      DashboardTaskGroup.posta,
      DashboardTaskColor.black,
      0,
    ),
    task(
      '12',
      'Conferma iscrizione al corso',
      DashboardTaskGroup.posta,
      DashboardTaskColor.black,
      1,
    ),
  ];

  DashboardTask task(
    String id,
    String title,
    DashboardTaskGroup group,
    DashboardTaskColor color,
    int offset, {
    bool done = false,
  }) => DashboardTask(
    id: 'demo-$id',
    title: title,
    group: group,
    color: color,
    scheduledDate: day.add(Duration(days: offset)),
    createdAt: day.subtract(const Duration(days: 3)),
    completedAt: done ? day : null,
  );

  @override
  Future<List<DashboardTask>> load() async => items;
  @override
  Stream<List<DashboardTask>> watch() => const Stream.empty();
  @override
  Future<void> save(List<DashboardTask> tasks) async => items = tasks;
  @override
  Future<void> delete(String id) async =>
      items = items.where((t) => t.id != id).toList();
}

// Calendar arithmetic that stays on midnight across daylight saving changes.
DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

DateTime _daysAgo(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - days);
}
