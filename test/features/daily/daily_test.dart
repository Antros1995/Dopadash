import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/daily/domain/daily_models.dart';
import 'package:monitoraggio_personale_desktop/features/routines/application/routine_controller.dart';
import 'package:monitoraggio_personale_desktop/features/routines/data/routine_repository.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine.dart';

class _Routines implements RoutineRepository {
  List<RoutineDefinition>? savedHistory;
  Map<String, RoutineEntry>? savedEntries;
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
  }) async {
    savedHistory = history;
    savedEntries = entries;
  }
}

void main() {
  test('il tempo al cellulare si scrive in più modi', () {
    expect(parseMinutes('2:15'), 135);
    expect(parseMinutes('02:15'), 135);
    expect(parseMinutes('2.15'), 135);
    expect(parseMinutes('215'), 135);
    expect(parseMinutes('45'), 45);
    expect(parseMinutes('0:05'), 5);
    expect(parseMinutes('24:00'), 1440);
    expect(parseMinutes('25:00'), isNull);
    expect(parseMinutes('270'), isNull);
    expect(parseMinutes('abc'), isNull);
    expect(parseMinutes(''), isNull);
    expect(formatMinutes(135), '02:15');
  });

  test('le app escluse non contano e decidono la coppa del cellulare', () {
    const time = ScreenTime(
      totalMinutes: 240,
      exclusions: [
        ScreenTimeExclusion(id: 'a', name: 'Duolingo', minutes: 180),
      ],
    );
    expect(time.countedMinutes, 60);
    expect(time.medal, ScreenTimeMedal.diamond);
    expect(ScreenTimeMedal.fromMinutes(89), ScreenTimeMedal.diamond);
    expect(ScreenTimeMedal.fromMinutes(90), ScreenTimeMedal.platinum);
    expect(ScreenTimeMedal.fromMinutes(164), ScreenTimeMedal.gold);
    expect(ScreenTimeMedal.fromMinutes(179), ScreenTimeMedal.silver);
    expect(ScreenTimeMedal.fromMinutes(224), ScreenTimeMedal.bronze);
    expect(ScreenTimeMedal.fromMinutes(225), ScreenTimeMedal.tooMuch);
  });

  test('la coppa del giorno usa le soglie dell’app per iPhone', () {
    expect(DayMedal.fromRate(.19), DayMedal.none);
    expect(DayMedal.fromRate(.20), DayMedal.bronze);
    expect(DayMedal.fromRate(.50), DayMedal.silver);
    expect(DayMedal.fromRate(.70), DayMedal.gold);
    expect(DayMedal.fromRate(.80), DayMedal.platinum);
    expect(DayMedal.fromRate(.90), DayMedal.diamond);
    expect(DayMedal.diamond.next, isNull);
    expect(DayMedal.gold.next, DayMedal.platinum);
  });

  test('le righe non valide del database vengono scartate', () {
    expect(EmotionEntry.fromRow({'id': 'x', 'emotion': 'boh'}), isNull);
    final entry = EmotionEntry.fromRow({
      'id': 'x',
      'emotion': 'calm',
      'intensity': 9,
      'energy': 'high',
      'recorded_at': '2026-11-13T09:00:00Z',
    })!;
    expect(entry.emotion, DailyEmotion.calm);
    expect(entry.intensity, 5);
    expect(
      ConcentrationEntry.fromRow({
        'id': 'c',
        'concentration': 4,
        'recorded_at': '2026-11-13T09:00:00Z',
        'source_key': 'emotion:abc',
      })!.fromEmotion,
      isTrue,
    );
    expect(
      ScreenTimeExclusion.fromJson({'id': 'a', 'name': ' ', 'minutes': 5}),
      isNull,
    );
  });

  test('i giorni si spostano per calendario, anche con il cambio di ora', () {
    // 25 ottobre 2026: in Italia il giorno dura 25 ore. Sottraendo 24 ore alla
    // volta si finiva all'01:00 e le date non coincidevano più con quelle salvate.
    var day = DateTime(2026, 11, 13);
    for (var i = 0; i < 300; i++) {
      day = shiftDays(day, -1);
      expect([day.hour, day.minute], [0, 0]);
    }
    expect(day, DateTime(2026, 1, 17));
    expect(shiftDays(DateTime(2026, 3, 30), -1), DateTime(2026, 3, 29));
    expect(shiftDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
  });

  group('abitudini', () {
    final day = DateTime(2026, 11, 13);
    late _Routines repository;
    late RoutineController controller;

    setUp(() {
      repository = _Routines();
      controller = RoutineController(
        repository: repository,
        initialDate: day,
        now: () => DateTime(2026, 11, 13, 8, 30),
      );
    });

    test('fatta, non fatta e di nuovo da fare', () async {
      await controller.setStatus('palestra', RoutineStatus.ok);
      expect(controller.entryFor('palestra').completionTimeMinutes, 510);
      final plan = defaultGymOptions[1];
      await controller.setDetail('palestra', plan);
      expect(
        repository.savedEntries!['palestra']!.selectedDetailOptionId,
        plan.id,
      );
      await controller.setStatus('palestra', RoutineStatus.ko);
      expect(controller.entryFor('palestra').completionTimeMinutes, isNull);
      await controller.setStatus('palestra', RoutineStatus.unmarked);
      final entry = controller.entryFor('palestra');
      expect(entry.isMarked, isFalse);
      expect(entry.selectedDetailOptionId, isNull);
    });

    test('aggiungere e togliere senza toccare lo storico', () async {
      final before = controller.routines.length;
      await controller.addRoutine(name: '  Stretching ');
      final added = controller.routines.last;
      expect(added.name, 'Stretching');
      expect(added.validFrom, day);
      expect(controller.routines.length, before + 1);

      // Nata oggi: sparisce del tutto.
      await controller.removeRoutine(added.id);
      expect(repository.savedHistory!.any((r) => r.id == added.id), isFalse);

      // Esistente da prima: resta nello storico, chiusa da oggi.
      await controller.removeRoutine('libro');
      expect(controller.routines.any((r) => r.id == 'libro'), isFalse);
      final closed = repository.savedHistory!.lastWhere((r) => r.id == 'libro');
      expect(closed.validUntil, day);
      expect(closed.isValidOn(day.subtract(const Duration(days: 1))), isTrue);
    });
  });
}
