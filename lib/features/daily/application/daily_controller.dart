import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../routines/domain/routine.dart' show dateOnly, shiftDays;
import '../data/daily_repository.dart';
import '../domain/daily_models.dart';

/// Stato della scheda Quotidianità (emozioni, concentrazione, movimento,
/// cellulare) e delle misure del corpo della scheda Sport.
class DailyController extends ChangeNotifier {
  DailyController({
    required this.repository,
    DateTime? initialDate,
    DateTime Function()? now,
    this.onScreenTimeChanged,
  }) : _now = now ?? DateTime.now,
       _date = dateOnly(initialDate ?? (now ?? DateTime.now)());

  final DailyRepository repository;
  final DateTime Function() _now;

  /// Il tempo al cellulare entra nel punteggio delle abitudini.
  final VoidCallback? onScreenTimeChanged;

  DateTime _date;
  DailyLifeDay _day = const DailyLifeDay();
  List<BodyMeasurement> _measurements = const [];
  bool _loading = false, _loaded = false, _disposed = false;
  bool _measurementsLoaded = false;
  int _busy = 0, _request = 0;
  Object? _error;
  StreamSubscription<void>? _remote;
  Timer? _debounce;

  DateTime get date => _date;
  DateTime get today => dateOnly(_now());
  bool get isToday => _date == today;
  DailyLifeDay get day => _day;
  List<BodyMeasurement> get measurements => _measurements;
  bool get isLoading => _loading && !_loaded;
  bool get isSaving => _busy > 0;
  bool get measurementsLoaded => _measurementsLoaded;

  /// Ultimo errore di lettura o salvataggio, da mostrare con "Riprova".
  Object? get error => _error;

  void start() {
    unawaited(load());
    _remote = repository.watchChanges().listen((_) {
      // Più tabelle cambiano insieme: una sola rilettura.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), refresh);
    });
  }

  Future<void> selectDate(DateTime date) async {
    final next = dateOnly(date);
    if (next == _date) return;
    _date = next;
    _day = const DailyLifeDay();
    _loaded = false;
    _notify();
    await load();
  }

  Future<void> load() async {
    final request = ++_request, date = _date;
    _loading = true;
    _notify();
    try {
      final day = await repository.fetchDay(date);
      if (request != _request || _disposed) return;
      _day = day;
      _loaded = true;
      _error = null;
    } catch (e) {
      if (request != _request || _disposed) return;
      _error = e;
    } finally {
      if (request == _request) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Rilettura silenziosa: dopo un salvataggio o un cambio da un altro
  /// dispositivo.
  Future<void> refresh() async {
    if (_disposed) return;
    await Future.wait([load(), if (_measurementsLoaded) loadMeasurements()]);
  }

  Future<void> loadMeasurements() async {
    try {
      final rows = await repository.loadMeasurements();
      if (_disposed) return;
      _measurements = [...rows]..sort((a, b) => a.date.compareTo(b.date));
      _measurementsLoaded = true;
      _error = null;
    } catch (e) {
      _error = e;
    }
    _notify();
  }

  Future<bool> _write(Future<void> Function() action, {bool body = false}) async {
    _busy++;
    _error = null;
    _notify();
    var ok = true;
    try {
      await action();
    } catch (e) {
      _error = e;
      ok = false;
    }
    _busy--;
    if (ok) await (body ? loadMeasurements() : load());
    _notify();
    return ok;
  }

  Future<bool> addEmotion({
    required DailyEmotion emotion,
    required int intensity,
    required DailyEnergy energy,
    int? concentration,
  }) => _write(
    () => repository.addEmotion(
      date: _date,
      emotion: emotion,
      intensity: intensity,
      energy: energy,
      concentration: concentration,
    ),
  );

  Future<bool> deleteEmotion(String id) =>
      _write(() => repository.deleteEmotion(id));

  Future<bool> addConcentration(ConcentrationKind kind, int level) =>
      _write(() => repository.addConcentration(kind, _date, level));

  Future<bool> deleteConcentration(ConcentrationKind kind, String id) =>
      _write(() => repository.deleteConcentration(kind, id));

  Future<bool> saveMovement(int level) {
    // Risposta immediata al tocco; la rilettura conferma.
    _day = DailyLifeDay(
      emotions: _day.emotions,
      dayConcentration: _day.dayConcentration,
      meditationConcentration: _day.meditationConcentration,
      movement: level,
      screenTime: _day.screenTime,
    );
    return _write(() => repository.saveMovement(_date, level));
  }

  /// Salva l'uso del cellulare del giorno prima di quello mostrato.
  Future<bool> saveScreenTime(ScreenTime? value) async {
    final ok = await _write(
      () => repository.saveScreenTime(
        shiftDays(_date, -1),
        value,
      ),
    );
    if (ok) onScreenTimeChanged?.call();
    return ok;
  }

  Future<bool> saveMeasurement(BodyMeasurement measurement) =>
      _write(() => repository.saveMeasurement(measurement), body: true);

  Future<bool> deleteMeasurement(DateTime date) =>
      _write(() => repository.deleteMeasurement(date), body: true);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_remote?.cancel());
    super.dispose();
  }
}
