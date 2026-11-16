import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/data_export/data/export_workbook_builder.dart';
import 'package:monitoraggio_personale_desktop/features/data_export/domain/export_selection.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/domain/fitbit_day.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine.dart';

void main() {
  test('creates only the selected Fitbit and checklist sheets', () {
    final date = DateTime(2026, 9, 15);
    final bytes = const ExportWorkbookBuilder().build(
      ExportWorkbookInput(
        start: date,
        end: date,
        fitbitFields: const {
          FitbitExportField.steps,
          FitbitExportField.workouts,
        },
        fitbitDays: {date: _fitbitDay()},
        routineIds: const {'palestra'},
        routineHistory: const [
          RoutineDefinition(
            id: 'palestra',
            name: 'Palestra',
            iconKey: 'gym',
            position: 1,
          ),
        ],
        routineEntries: {
          date: const {
            'palestra': RoutineEntry(
              status: RoutineStatus.ok,
              completionTimeMinutes: 18 * 60 + 30,
              selectedDetailLabelSnapshot: 'Scheda A',
            ),
          },
        },
      ),
    );

    final workbook = Excel.decodeBytes(bytes);
    expect(
      workbook.tables.keys,
      containsAll(['Dati orologio', 'Allenamenti', 'Checklist']),
    );
    expect(workbook.tables.keys, isNot(contains('Profilo cardiaco')));
    expect(workbook['Dati orologio'].maxRows, 2);
    expect(workbook['Allenamenti'].maxRows, 2);
    expect(workbook['Checklist'].maxRows, 2);
    expect(
      workbook['Dati orologio'].cell(CellIndex.indexByString('D2')).value,
      IntCellValue(8432),
    );
    expect(
      workbook['Dati orologio'].cell(CellIndex.indexByString('B2')).value,
      TextCellValue('Fitbit'),
    );
    expect(
      workbook['Checklist'].cell(CellIndex.indexByString('B2')).value,
      TextCellValue('Palestra'),
    );
  });
}

FitbitDay _fitbitDay() => FitbitDay(
  date: '2026-09-15',
  finalized: true,
  syncedAt: DateTime(2026, 9, 15, 23),
  steps: 8432,
  distanceKm: 6.2,
  calories: 2200,
  activeMinutes: 54,
  restingHeartRate: 58,
  sleepMinutes: 445,
  sleepEfficiency: 91,
  workouts: [
    FitbitWorkout(
      type: 'WEIGHT_TRAINING',
      name: 'Palestra',
      startTime: DateTime(2026, 9, 15, 18, 30),
      activeMinutes: 62,
      calories: 410,
      distanceKm: null,
      averageHeartRate: 119,
    ),
  ],
);
