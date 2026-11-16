import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/data_export/presentation/data_export_page.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/domain/fitbit_day.dart';
import 'package:monitoraggio_personale_desktop/features/routines/application/routine_controller.dart';
import 'package:monitoraggio_personale_desktop/features/routines/data/routine_repository.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine.dart';

void main() {
  testWidgets('export page is usable at smartphone width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final routines = RoutineController(repository: _RoutineRepository());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: DataExportPage(
            routines: routines,
            fitbitRepository: _FitbitRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Esporta dati'), findsOneWidget);
    expect(find.text('Dati orologio'), findsOneWidget);
    expect(find.text('Checklist e abitudini'), findsOneWidget);
    expect(find.text('Passi'), findsOneWidget);
    expect(find.text('Allenamento'), findsOneWidget);
    expect(find.byKey(const ValueKey('export-data-button')), findsOneWidget);
  });
}

class _RoutineRepository implements RoutineRepository {
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
  }) async => const {};

  @override
  Future<void> saveDay({
    required DateTime date,
    required List<RoutineDefinition> history,
    required Map<String, RoutineEntry> entries,
  }) async {}
}

class _FitbitRepository implements FitbitRepository {
  @override
  bool get isConfigured => true;

  @override
  Future<Uri> beginConnect() async => Uri.parse('https://example.com');

  @override
  void dispose() {}

  @override
  Future<FitbitStatus> fetchDay(DateTime date) async => const FitbitStatus(
    configured: true,
    connection: 'CONNECTED',
    deviceName: 'Charge 6',
    day: null,
  );

  @override
  Future<FitbitStatus> saveMindfulnessMinutes(DateTime date, int? minutes) =>
      fetchDay(date);
}
