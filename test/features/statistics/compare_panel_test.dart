import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/application/fitbit_controller.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/application/body_statistics_controller.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/data/compare_sources.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/presentation/body_statistics_page.dart';
import 'body_statistics_test.dart' show MemoryStatisticsRepository, day;

class _Fitbit implements FitbitRepository {
  @override
  bool get isConfigured => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Meditazione nei giorni pari, concentrazione che sale con l'HRV.
class _Sources implements CompareSources {
  final asked = <CompareSource>[];
  @override
  Future<Map<String, double>> load(
    CompareSource source,
    DateTime start,
    DateTime end,
  ) async {
    asked.add(source);
    return {
      for (var d = 1; d <= 14; d++)
        '2026-10-${d.toString().padLeft(2, '0')}': switch (source) {
          CompareSource.meditation => d.isEven ? 1 : 0,
          CompareSource.dayConcentration => 1 + d / 4,
          _ => 2,
        },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('overview compare panel opens and adapts to the parameters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryStatisticsRepository()
      ..days = [
        for (var d = 1; d <= 14; d++)
          // HRV più alta nei giorni pari (con meditazione).
          day(
            '2026-10-${d.toString().padLeft(2, '0')}',
            hrv: d.isEven ? 60 : 40,
          ),
      ]
      ..preferences = {'section': 'Panoramica', 'period': 'month'};
    final c = BodyStatisticsController(
      repository: repo,
      clock: () => DateTime(2026, 10, 14),
    );
    final fitbit = FitbitController(repository: _Fitbit());
    final sources = _Sources();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: BodyStatisticsPage(
            controller: c,
            fitbit: fitbit,
            compareSources: sources,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Chiuso finché non lo apri.
    expect(find.text('Confronta parametri'), findsOneWidget);
    expect(find.text('💡 Cosa vedo'), findsNothing);
    await tester.ensureVisible(find.text('Apri'));
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();

    // HRV · Meditazione: vista «con / senza» con le medie dei due gruppi.
    expect(sources.asked, contains(CompareSource.meditation));
    expect(find.text('💡 Cosa vedo'), findsOneWidget);
    expect(
      find.textContaining('Nei giorni con 🧘 meditazione'),
      findsOneWidget,
    );
    expect(find.text('60 ms'), findsOneWidget);
    expect(find.text('40 ms'), findsOneWidget);

    // HRV · Concentrazione: due valori continui → legame e grafico nel tempo.
    await tester.tap(find.text('❤️ HRV · 🎯 Concentrazione'));
    await tester.pumpAndSettle();
    expect(sources.asked, contains(CompareSource.dayConcentration));
    expect(find.textContaining('r = '), findsOneWidget);
    expect(find.text('🔵 Uno contro l’altro'), findsOneWidget);
    await tester.tap(find.text('🔵 Uno contro l’altro'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ogni punto è un giorno'), findsOneWidget);

    // Un quarto parametro non entra: avviso gentile.
    await tester.tap(find.text('😴 Sonno · ⚡ Energia · 🎯 Concentrazione'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('👟 Passi'));
    await tester.tap(find.text('👟 Passi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('al massimo 3 parametri'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    fitbit.dispose();
  });
}
