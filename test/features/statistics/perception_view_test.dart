import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/application/fitbit_controller.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/application/body_statistics_controller.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/presentation/body_statistics_page.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/presentation/statistics_charts.dart';
import 'body_statistics_test.dart' show MemoryStatisticsRepository;
import 'perception_statistics_test.dart' show emotion;

class _NoFitbit implements FitbitRepository {
  @override
  bool get isConfigured => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets(
    'Percezione filters the diary, paginates history and refreshes without Fitbit',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryStatisticsRepository()
        ..preferences = {'section': 'Percezione', 'period': 'month'}
        ..perceptions = [
          for (var i = 1; i <= 20; i++)
            emotion(
              'e-$i',
              '2026-10-${i.toString().padLeft(2, '0')}',
              i.isEven ? 'calm' : 'happy',
              i.isEven ? 4 : 2,
            ),
          emotion('older', '2026-09-20', 'calm', 1),
          emotion('future', '2026-10-21', 'calm', 5),
        ];
      final c = BodyStatisticsController(
        repository: repo,
        clock: () => DateTime(2026, 10, 20),
      );
      final fitbit = FitbitController(repository: _NoFitbit());
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
        find.byKey(const ValueKey('perception-intensity-chart')),
      );
      expect(bodySections.map((s) => s.$1).toList(), [
        'Panoramica',
        'Sonno',
        'Cuore e recupero',
        'Attività',
        'Percezione',
        'Abitudini',
        'Cellulare',
        'Sport',
        'Esperimenti',
      ]);
      expect(chart().values.whereType<double>().length, 20);
      expect(chart().previous!.whereType<double>().toList(), [1]);
      expect(
        find.byKey(const ValueKey('perception-entry-future')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('perception-entry-older')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('perception-entry-e-1')), findsNothing);
      final next = find.byTooltip('Altre registrazioni');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('perception-entry-e-1')),
        findsOneWidget,
      );
      c.change(() => c.perceptionEmotion = 'calm');
      await tester.pumpAndSettle();
      expect(
        chart().values.whereType<double>().toList(),
        List<double>.filled(10, 4),
      );
      expect(
        find.byKey(const ValueKey('perception-entry-e-2')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('perception-entry-e-1')), findsNothing);
      repo.perceptions = [emotion('updated', '2026-10-20', 'calm', 3)];
      final refresh = find.byTooltip('Aggiorna le emozioni dal diario');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(chart().values.whereType<double>().toList(), [3]);
      expect(chart().bars, isTrue);
      expect(c.syncError, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      fitbit.dispose();
    },
  );
}
