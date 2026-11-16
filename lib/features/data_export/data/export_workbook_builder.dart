import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../fitbit/domain/daily_performance.dart';
import '../../fitbit/domain/fitbit_day.dart';
import '../../routines/domain/routine.dart';
import '../domain/export_selection.dart';
import 'diet_export.dart';

class ExportWorkbookInput {
  const ExportWorkbookInput({
    required this.start,
    required this.end,
    required this.fitbitFields,
    required this.fitbitDays,
    required this.routineIds,
    required this.routineHistory,
    required this.routineEntries,
    this.dietParts = const {},
    this.dietState,
  });

  final DateTime start;
  final DateTime end;
  final Set<FitbitExportField> fitbitFields;
  final Map<DateTime, FitbitDay> fitbitDays;
  final Set<String> routineIds;
  final List<RoutineDefinition> routineHistory;
  final Map<DateTime, Map<String, RoutineEntry>> routineEntries;

  /// Fogli dell'Alimentazione da aggiungere e lo stato della dieta.
  final Set<DietExportPart> dietParts;
  final Map<String, dynamic>? dietState;
}

class ExportWorkbookBuilder {
  const ExportWorkbookBuilder();

  Uint8List build(ExportWorkbookInput input) {
    final workbook = Excel.createExcel();
    var firstSheet = true;

    void addSheet(String name, void Function(Sheet sheet) fill) {
      final sheet = workbook[name];
      fill(sheet);
      if (firstSheet) {
        workbook.setDefaultSheet(name);
        firstSheet = false;
      }
    }

    if (input.fitbitFields.isNotEmpty) {
      addSheet('Dati orologio', (sheet) => _fillFitbitDaily(sheet, input));
      if (input.fitbitFields.contains(FitbitExportField.workouts)) {
        addSheet('Allenamenti', (sheet) => _fillWorkouts(sheet, input));
      }
      if (input.fitbitFields.contains(FitbitExportField.heartProfile)) {
        addSheet(
          'Profilo cardiaco',
          (sheet) => _fillHeartProfile(sheet, input),
        );
      }
      if (input.fitbitFields.contains(FitbitExportField.sleepStages)) {
        addSheet('Fasi sonno', (sheet) => _fillSleepStages(sheet, input));
      }
    }
    if (input.routineIds.isNotEmpty) {
      addSheet('Checklist', (sheet) => _fillChecklist(sheet, input));
    }
    if (input.dietState case final diet?) {
      final sheets = DietSheets(diet, input.start, input.end);
      final parts = input.dietParts;
      if (parts.contains(DietExportPart.daily)) {
        addSheet('Dieta - calorie', sheets.fillDaily);
      }
      if (parts.contains(DietExportPart.meals)) {
        addSheet('Dieta - pasti', sheets.fillMeals);
      }
      if (parts.contains(DietExportPart.extras)) {
        addSheet('Dieta - fuori piano', sheets.fillExtras);
      }
      if (parts.contains(DietExportPart.plans)) {
        addSheet('Dieta - piani', sheets.fillPlans);
      }
      if (parts.contains(DietExportPart.saved)) {
        addSheet('Dieta - combinazioni', sheets.fillSaved);
      }
    }

    if (workbook.tables.length > 1 && workbook.tables.containsKey('Sheet1')) {
      workbook.delete('Sheet1');
    }
    final bytes = workbook.save();
    if (bytes == null) throw StateError('Impossibile generare il file Excel.');
    return Uint8List.fromList(bytes);
  }

  void _fillFitbitDaily(Sheet sheet, ExportWorkbookInput input) {
    final columns = _dailyColumns(input.fitbitFields);
    _appendHeader(sheet, [
      'Data',
      'Fonte',
      'Dati disponibili',
      ...columns.map((e) => e.label),
    ]);
    for (final date in _dates(input.start, input.end)) {
      final day = input.fitbitDays[dateOnly(date)];
      sheet.appendRow([
        _dateCell(date),
        day == null ? null : TextCellValue('Fitbit'),
        BoolCellValue(day != null),
        for (final column in columns) column.value(day),
      ]);
    }
    _sizeColumns(sheet, 3 + columns.length);
  }

  void _fillWorkouts(Sheet sheet, ExportWorkbookInput input) {
    _appendHeader(sheet, [
      'Data',
      'Ora inizio',
      'Tipo',
      'Nome',
      'Minuti attivi',
      'Calorie (kcal)',
      'Distanza (km)',
      'FC media (bpm)',
    ]);
    for (final date in _dates(input.start, input.end)) {
      for (final workout
          in input.fitbitDays[dateOnly(date)]?.workouts ??
              const <FitbitWorkout>[]) {
        sheet.appendRow([
          _dateCell(date),
          _dateTimeCell(workout.startTime),
          TextCellValue(workout.type),
          _text(workout.name),
          IntCellValue(workout.activeMinutes),
          _integer(workout.calories),
          _decimal(workout.distanceKm),
          _integer(workout.averageHeartRate),
        ]);
      }
    }
    _sizeColumns(sheet, 8);
  }

  void _fillHeartProfile(Sheet sheet, ExportWorkbookInput input) {
    _appendHeader(sheet, [
      'Data',
      'Intervallo',
      'FC media (bpm)',
      'FC minima (bpm)',
      'FC massima (bpm)',
    ]);
    for (final date in _dates(input.start, input.end)) {
      for (final point
          in input.fitbitDays[dateOnly(date)]?.heartProfile ??
              const <FitbitHeartPoint>[]) {
        sheet.appendRow([
          _dateCell(date),
          _dateTimeCell(point.startTime),
          DoubleCellValue(point.average),
          DoubleCellValue(point.minimum),
          DoubleCellValue(point.maximum),
        ]);
      }
    }
    _sizeColumns(sheet, 5);
  }

  void _fillSleepStages(Sheet sheet, ExportWorkbookInput input) {
    _appendHeader(sheet, [
      'Data',
      'Inizio',
      'Fine',
      'Fase del sonno',
      'Durata (min)',
    ]);
    for (final date in _dates(input.start, input.end)) {
      for (final stage
          in input.fitbitDays[dateOnly(date)]?.sleepStages ??
              const <FitbitSleepStage>[]) {
        final duration = stage.endTime.difference(stage.startTime).inMinutes;
        sheet.appendRow([
          _dateCell(date),
          _dateTimeCell(stage.startTime),
          _dateTimeCell(stage.endTime),
          TextCellValue(stage.type),
          IntCellValue(duration),
        ]);
      }
    }
    _sizeColumns(sheet, 5);
  }

  void _fillChecklist(Sheet sheet, ExportWorkbookInput input) {
    _appendHeader(sheet, [
      'Data',
      'Checklist',
      'Stato',
      'Completata',
      'Ora registrata',
      'Dettaglio',
      'Punteggio dettaglio',
      'Note',
    ]);
    for (final date in _dates(input.start, input.end)) {
      final entries =
          input.routineEntries[dateOnly(date)] ??
          const <String, RoutineEntry>{};
      final definitions = <String, RoutineDefinition>{};
      for (final definition in input.routineHistory) {
        if (input.routineIds.contains(definition.id) &&
            definition.isValidOn(date)) {
          definitions[definition.id] = definition;
        }
      }
      final ordered = definitions.values.toList()
        ..sort((left, right) => left.position.compareTo(right.position));
      for (final definition in ordered) {
        final entry = entries[definition.id] ?? const RoutineEntry();
        sheet.appendRow([
          _dateCell(date),
          TextCellValue(definition.name),
          TextCellValue(_routineStatus(entry.status)),
          entry.status == RoutineStatus.unmarked
              ? null
              : BoolCellValue(entry.isCompleted),
          _time(entry.completionTimeMinutes),
          _text(entry.selectedDetailLabelSnapshot),
          _decimal(entry.selectedDetailScoreSnapshot),
          _text(entry.notes.isEmpty ? null : entry.notes),
        ]);
      }
    }
    _sizeColumns(sheet, 8);
  }

  List<_DailyColumn> _dailyColumns(Set<FitbitExportField> selected) {
    final result = <_DailyColumn>[];
    void add(
      FitbitExportField field,
      String label,
      CellValue? Function(FitbitDay) value,
    ) {
      if (selected.contains(field)) result.add(_DailyColumn(label, value));
    }

    add(FitbitExportField.steps, 'Passi', (day) => IntCellValue(day.steps));
    add(
      FitbitExportField.distance,
      'Distanza (km)',
      (day) => DoubleCellValue(day.distanceKm),
    );
    add(
      FitbitExportField.calories,
      'Calorie (kcal)',
      (day) => IntCellValue(day.calories),
    );
    add(
      FitbitExportField.activeMinutes,
      'Minuti attivi',
      (day) => IntCellValue(day.activeMinutes),
    );
    add(
      FitbitExportField.sedentaryMinutes,
      'Minuti sedentari',
      (day) => _integer(day.sedentaryMinutes),
    );
    add(
      FitbitExportField.activeZones,
      'Zona brucia grassi (min)',
      (day) => _integer(day.activeZoneMinutesByZone?.fatBurn),
    );
    add(
      FitbitExportField.activeZones,
      'Zona cardio (min)',
      (day) => _integer(day.activeZoneMinutesByZone?.cardio),
    );
    add(
      FitbitExportField.activeZones,
      'Zona picco (min)',
      (day) => _integer(day.activeZoneMinutesByZone?.peak),
    );
    add(
      FitbitExportField.restingHeartRate,
      'FC a riposo (bpm)',
      (day) => _integer(day.restingHeartRate),
    );
    add(
      FitbitExportField.sleep,
      'Sonno (min)',
      (day) => _integer(day.sleepMinutes),
    );
    add(
      FitbitExportField.sleep,
      'Efficienza sonno (%)',
      (day) => _integer(day.sleepEfficiency),
    );
    add(
      FitbitExportField.sleepDetails,
      'Inizio sonno',
      (day) => _dateTime(day.sleepDetails?.startTime),
    );
    add(
      FitbitExportField.sleepDetails,
      'Fine sonno',
      (day) => _dateTime(day.sleepDetails?.endTime),
    );
    add(
      FitbitExportField.sleepDetails,
      'Tempo a letto (min)',
      (day) => _integer(day.sleepDetails?.minutesInSleepPeriod),
    );
    add(
      FitbitExportField.sleepDetails,
      'Veglia (min)',
      (day) => _integer(day.sleepDetails?.minutesAwake),
    );
    add(
      FitbitExportField.sleepDetails,
      'Sonno leggero (min)',
      (day) => _integer(day.sleepDetails?.stageMinutes.light),
    );
    add(
      FitbitExportField.sleepDetails,
      'Sonno profondo (min)',
      (day) => _integer(day.sleepDetails?.stageMinutes.deep),
    );
    add(
      FitbitExportField.sleepDetails,
      'Sonno REM (min)',
      (day) => _integer(day.sleepDetails?.stageMinutes.rem),
    );
    add(
      FitbitExportField.sleepDetails,
      'Tempo addormentamento (min)',
      (day) => _integer(day.sleepDetails?.minutesToFallAsleep),
    );
    add(
      FitbitExportField.sleepDetails,
      'Tempo dopo risveglio (min)',
      (day) => _integer(day.sleepDetails?.minutesAfterWakeUp),
    );
    add(
      FitbitExportField.oxygenSaturation,
      'SpO₂ media (%)',
      (day) => _decimal(day.oxygenSaturation?.average),
    );
    add(
      FitbitExportField.oxygenSaturation,
      'SpO₂ minima (%)',
      (day) => _decimal(day.oxygenSaturation?.minimum),
    );
    add(
      FitbitExportField.oxygenSaturation,
      'SpO₂ massima (%)',
      (day) => _decimal(day.oxygenSaturation?.maximum),
    );
    add(
      FitbitExportField.heartRateVariability,
      'HRV (ms)',
      (day) => _decimal(day.heartRateVariabilityMs),
    );
    add(
      FitbitExportField.respiratoryRate,
      'Respiri al minuto',
      (day) => _decimal(day.respiratoryRate),
    );
    add(
      FitbitExportField.skinTemperature,
      'Temperatura notturna (°C)',
      (day) => _decimal(day.skinTemperature?.nightlyCelsius),
    );
    add(
      FitbitExportField.skinTemperature,
      'Temperatura baseline (°C)',
      (day) => _decimal(day.skinTemperature?.baselineCelsius),
    );
    add(
      FitbitExportField.vo2Max,
      'VO₂ max',
      (day) => _decimal(day.vo2Max?.value),
    );
    add(
      FitbitExportField.vo2Max,
      'Livello fitness cardio',
      (day) => _text(day.vo2Max?.cardioFitnessLevel),
    );
    add(
      FitbitExportField.mindfulness,
      'Mindfulness (min)',
      (day) => _integer(day.mindfulnessMinutes),
    );
    add(
      FitbitExportField.recovery,
      'Recupero (0-100)',
      (day) => _integer(DailyPerformance.fromFitbit(day).recoveryScore),
    );
    add(
      FitbitExportField.cardioLoad,
      'Carico cardio (0-21)',
      (day) => _decimal(DailyPerformance.fromFitbit(day).cardioLoad),
    );
    add(
      FitbitExportField.sleepPerformance,
      'Qualità sonno (0-100)',
      (day) => _integer(DailyPerformance.fromFitbit(day).sleepPerformance),
    );
    add(
      FitbitExportField.sleepDebt,
      'Debito sonno (min)',
      (day) => _integer(DailyPerformance.fromFitbit(day).sleepDebtMinutes),
    );
    return result;
  }

  void _appendHeader(Sheet sheet, List<String> labels) {
    sheet.appendRow([for (final label in labels) TextCellValue(label)]);
    final style = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#FF357155'),
      verticalAlign: VerticalAlign.Center,
    );
    for (final cell in sheet.row(0)) {
      cell?.cellStyle = style;
    }
  }

  void _sizeColumns(Sheet sheet, int count) {
    for (var index = 0; index < count; index++) {
      sheet.setColumnWidth(index, index == 0 ? 13 : 22);
    }
  }
}

class _DailyColumn {
  const _DailyColumn(this.label, CellValue? Function(FitbitDay) value)
    : _value = value;

  final String label;
  final CellValue? Function(FitbitDay) _value;

  CellValue? value(FitbitDay? day) => day == null ? null : _value(day);
}

Iterable<DateTime> _dates(DateTime start, DateTime end) sync* {
  var current = dateOnly(start);
  final last = dateOnly(end);
  while (!current.isAfter(last)) {
    yield current;
    current = current.add(const Duration(days: 1));
  }
}

DateCellValue _dateCell(DateTime value) =>
    DateCellValue(year: value.year, month: value.month, day: value.day);

DateTimeCellValue _dateTimeCell(DateTime value) => DateTimeCellValue(
  year: value.year,
  month: value.month,
  day: value.day,
  hour: value.hour,
  minute: value.minute,
  second: value.second,
  millisecond: value.millisecond,
);

CellValue? _dateTime(DateTime? value) =>
    value == null ? null : _dateTimeCell(value);
CellValue? _text(String? value) => value == null ? null : TextCellValue(value);
CellValue? _integer(int? value) => value == null ? null : IntCellValue(value);
CellValue? _decimal(num? value) =>
    value == null ? null : DoubleCellValue(value.toDouble());

CellValue? _time(int? minutes) {
  if (minutes == null) return null;
  return TimeCellValue(hour: minutes ~/ 60, minute: minutes % 60);
}

String _routineStatus(RoutineStatus status) => switch (status) {
  RoutineStatus.ok => 'Completata',
  RoutineStatus.ko => 'Non completata',
  RoutineStatus.unmarked => 'Non registrata',
};
