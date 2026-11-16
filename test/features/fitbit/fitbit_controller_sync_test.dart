import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/application/fitbit_controller.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/domain/fitbit_day.dart';

FitbitStatus _status(String date, int minutes) => FitbitStatus.fromJson({
  'configured': true,
  'connection': 'CONNECTED',
  'day': {
    'date': date,
    'syncedAt': '2026-10-19T12:00:00Z',
    'finalized': false,
    'steps': 5000,
    'distanceKm': 4,
    'calories': 1500,
    'activeMinutes': 20,
    'mindfulnessMinutes': minutes,
  },
});

class _Repository implements FitbitRepository {
  Completer<FitbitStatus>? pending;
  @override
  bool get isConfigured => true;
  @override
  Future<FitbitStatus> fetchDay(DateTime date) =>
      pending?.future ?? Future.value(_status('2026-10-19', 5));
  @override
  Future<FitbitStatus> saveMindfulnessMinutes(
    DateTime date,
    int? minutes,
  ) async => _status('2026-10-19', minutes!);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test(
    'a late background response cannot overwrite a manually saved value',
    () async {
      final repo = _Repository();
      final controller = FitbitController(
        repository: repo,
        initialDate: DateTime(2026, 10, 19),
      );
      await controller.load();
      final pending = repo.pending = Completer<FitbitStatus>();
      final refresh = controller.load(background: true);
      expect(controller.isLoading, isFalse);
      await controller.saveMindfulnessMinutes(15);
      pending.complete(_status('2026-10-19', 5));
      await refresh;
      expect(controller.day!.mindfulnessMinutes, 15);
      expect(controller.isLoading, isFalse);
      controller.dispose();
    },
  );

  test(
    'closing the app while a request is pending ignores its late response',
    () async {
      final repo = _Repository()..pending = Completer<FitbitStatus>();
      final controller = FitbitController(repository: repo);
      final refresh = controller.load();
      controller.dispose();
      repo.pending!.complete(_status('2026-10-19', 5));
      await refresh;
    },
  );
}
