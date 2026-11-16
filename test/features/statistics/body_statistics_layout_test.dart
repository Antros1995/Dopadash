import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/application/fitbit_controller.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/application/body_statistics_controller.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/presentation/body_statistics_page.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/presentation/experiment_forms.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/body_statistics.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/perception_statistics.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/presentation/statistics_charts.dart';
import 'heart_rate_statistics_test.dart' show heartDay, point;
import 'body_statistics_test.dart'
    show MemoryStatisticsRepository, day, experiment;

class _Fitbit implements FitbitRepository {
  @override
  bool get isConfigured => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('phone period filters and chart values work by touch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryStatisticsRepository()
      ..days = [
        for (var i = 11; i <= 17; i++)
          heartDay('2026-10-$i', [point('2026-10-${i}T08:00:00Z', 60 + i)]),
      ]
      ..preferences = {'section': 'Cuore e recupero'};
    final c = BodyStatisticsController(
      repository: repo,
      clock: () => DateTime(2026, 10, 17),
    );
    final fitbit = FitbitController(repository: _Fitbit());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: BodyStatisticsPage(controller: c, fitbit: fitbit),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<BodyPeriod>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 giorni').last);
    await tester.pumpAndSettle();
    expect(c.period, BodyPeriod.week);
    final wasMoving = c.moving;
    await tester.tap(find.byTooltip('Filtri e confronto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(c.moving, !wasMoving);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nessun confronto').last);
    await tester.pumpAndSettle();
    expect(c.compare, isFalse);
    await tester.tap(find.text('Fatto'));
    await tester.pumpAndSettle();
    final chart = find.byKey(const ValueKey('heart-rate-period-chart'));
    await tester.ensureVisible(chart);
    await tester.tapAt(tester.getTopLeft(chart) + const Offset(180, 90));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: chart, matching: find.textContaining('bpm')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    fitbit.dispose();
  });
  testWidgets(
    'heart rate chart follows month, average-day mode, comparison and 24-hour selection',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryStatisticsRepository()
        ..days = [
          heartDay('2026-09-01', [point('2026-09-01T08:00:00Z', 50)]),
          heartDay('2026-10-01', [point('2026-10-01T08:00:00Z', 60)]),
          heartDay('2026-10-17', [point('2026-10-17T08:00:00Z', 100)]),
        ]
        ..preferences = {'section': 'Cuore e recupero'};
      final c = BodyStatisticsController(
        repository: repo,
        clock: () => DateTime(2026, 10, 17),
      );
      final fitbit = FitbitController(repository: _Fitbit());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: BodyStatisticsPage(controller: c, fitbit: fitbit),
          ),
        ),
      );
      await tester.pumpAndSettle();
      BodyChart chart() => tester.widget<BodyChart>(
        find.byKey(const ValueKey('heart-rate-period-chart')),
      );
      expect(chart().values.length, 30);
      expect(chart().values.whereType<double>().toList(), [60, 100]);
      expect(chart().previous!.whereType<double>().toList(), [50]);
      expect(chart().average, isTrue);
      final averageButton = find.text('Giornata media');
      await tester.ensureVisible(averageButton);
      await tester.tap(averageButton);
      await tester.pumpAndSettle();
      expect(chart().values.length, 48);
      expect(chart().values[20], 80);
      expect(chart().previous![20], 50);
      expect(chart().average, isFalse);
      expect(chart().pointDetails![20], contains('2 / 30 giorni'));
      c.change(() => c.period = BodyPeriod.day);
      await tester.pumpAndSettle();
      expect(chart().values.whereType<double>().toList(), [100]);
      expect(chart().labels[20], '10:00');
      c.change(() {
        c.period = BodyPeriod.custom;
        c.customRange = BodyRange(DateTime(2026, 10, 1), DateTime(2026, 10, 2));
        c.averageHeartDay = false;
        c.compare = false;
      });
      await tester.pumpAndSettle();
      expect(chart().values, [60, null]);
      expect(chart().previous, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      fitbit.dispose();
    },
  );
  testWidgets(
    'experiment form saves a draft and diary corrections preserve unknown practice',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryStatisticsRepository();
      final c = BodyStatisticsController(
        repository: repo,
        clock: () => DateTime(2026, 10, 17),
      );
      final fitbit = FitbitController(repository: _Fitbit());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          locale: const Locale('it'),
          supportedLocales: const [Locale('it')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: BodyStatisticsPage(controller: c, fitbit: fitbit),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(BodyStatisticsPage));
      showExperimentForm(context, c);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Pratica di prova',
      );
      await tester.tap(find.text('Salva bozza'));
      await tester.pumpAndSettle();
      expect(c.selected!.name, 'Pratica di prova');
      expect(c.selected!.status, ExperimentStatus.draft);
      expect(c.logs, isEmpty);
      await c.saveLog(
        ExperimentLog(
          experimentId: c.selectedId!,
          date: c.today,
          calm: 6,
          notes: 'Nota esistente',
        ),
      );
      showLogForm(context, c);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Nota esistente'),
        ),
        findsOneWidget,
      );
      final stress = find.widgetWithText(
        TextFormField,
        'Stress percepito · 0–10',
      );
      await tester.ensureVisible(stress);
      await tester.enterText(stress, '0');
      await tester.tap(find.text('Salva giornata'));
      await tester.pumpAndSettle();
      expect(c.logs.single.stress, 0);
      expect(c.logs.single.calm, 6);
      expect(c.logs.single.sessionStatus, isNull);
      expect(c.logs.single.notes, 'Nota esistente');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      fitbit.dispose();
    },
  );
  for (final width in [328.0, 390.0, 1024.0, 1586.0]) {
    testWidgets(
      'all statistics views and forms fit at $width without browser',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = MemoryStatisticsRepository()
          ..days = [
            for (var i = 1; i <= 17; i++)
              day(
                '2026-10-${i.toString().padLeft(2, '0')}',
                hrv: 40 + i.toDouble(),
                steps: 1000,
              ),
          ]
          ..experiments = [experiment()];
        repo.perceptions = [
          for (var i = 1; i <= 17; i++)
            PerceptionEntry(
              id: '$i',
              date: DateTime.utc(2026, 10, i),
              emotion: i.isEven ? 'calm' : 'overwhelmed',
              intensity: 3,
              energy: 'medium',
              recordedAt: DateTime.utc(2026, 10, i, 16),
            ),
        ];
        final c = BodyStatisticsController(
          repository: repo,
          clock: () => DateTime(2026, 10, 17),
        );
        final fitbit = FitbitController(repository: _Fitbit());
        await tester.pumpWidget(
          MaterialApp(
            theme: buildDesktopTheme(),
            locale: const Locale('it'),
            supportedLocales: const [Locale('it')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: BodyStatisticsPage(controller: c, fitbit: fitbit),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final section in [
          'Panoramica',
          'Sonno',
          'Cuore e recupero',
          'Attività',
          'Percezione',
          'Esperimenti',
        ]) {
          c.change(() => c.section = section);
          if (section == 'Esperimenti') await c.selectExperiment('test');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: section);
        }
        final ctx = tester.element(find.byType(BodyStatisticsPage));
        showExperimentForm(ctx, c);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        Navigator.pop(tester.element(find.byType(AlertDialog)));
        await tester.pumpAndSettle();
        showLogForm(ctx, c);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        Navigator.pop(tester.element(find.byType(AlertDialog)));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        fitbit.dispose();
      },
    );
  }
}
