import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/routine_repository.dart';
import '../domain/routine.dart';
import '../domain/routine_progress.dart';

class RoutineController extends ChangeNotifier {
  RoutineController({
    required this.repository,
    DateTime? initialDate,
    DateTime Function()? now,
    List<RoutineDefinition>? initialHistory,
  }) : _selectedDate = dateOnly(initialDate ?? DateTime.now()),
       _now = now ?? DateTime.now,
       _history = List<RoutineDefinition>.of(
         initialHistory ?? buildDefaultRoutineHistory(),
       );

  final RoutineRepository repository;
  final DateTime Function() _now;
  DateTime _selectedDate;
  List<RoutineDefinition> _history;
  Map<String, RoutineEntry> _entries = <String, RoutineEntry>{};
  int? _effectiveScreenTimeMinutes;
  bool _isLoading = false;
  int _pendingSaves = 0;
  Object? _loadError;
  Object? _syncError;
  Future<void> _saveTail = Future<void>.value();
  Timer? _refreshTimer;
  Timer? _refreshDebounce;
  StreamSubscription<void>? _changeSubscription;
  bool _backgroundRefreshInFlight = false;
  bool _backgroundRefreshQueued = false;
  int _localRevision = 0;
  bool _disposed = false;
  final Map<DateTime, _RoutineWrite> _unsaved = {};

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  DateTime get selectedDate => _selectedDate;
  bool get isLoading => _isLoading;
  bool get isSaving => _pendingSaves > 0;
  Object? get loadError => _loadError;
  Object? get syncError => _syncError;
  int? get effectiveScreenTimeMinutes => _effectiveScreenTimeMinutes;
  List<RoutineDefinition> get history => List.unmodifiable(_history);

  List<RoutineDefinition> get routines {
    final result =
        _history
            .where((routine) => routine.isValidOn(_selectedDate))
            .toList(growable: false)
          ..sort((left, right) => left.position.compareTo(right.position));
    return List.unmodifiable(result);
  }

  Map<String, RoutineEntry> get entries => Map.unmodifiable(_entries);

  RoutineEntry entryFor(String routineId) =>
      _entries[routineId] ?? const RoutineEntry();

  RoutineProgress get progress => calculateRoutineProgress(
    definitions: routines,
    entries: _entries,
    effectiveScreenTimeMinutes: _effectiveScreenTimeMinutes,
  );

  Future<void> load() => _load(showProgress: true, reportFailure: true);

  Future<void> _load({
    required bool showProgress,
    required bool reportFailure,
  }) async {
    if (_disposed) return;
    final requestedDate = _selectedDate;
    final requestedRevision = _localRevision;
    if (showProgress) {
      _isLoading = true;
      _loadError = null;
      _notify();
    }
    try {
      final remote = await repository
          .fetchDay(requestedDate)
          .timeout(const Duration(seconds: 30));
      if (_disposed ||
          requestedDate != _selectedDate ||
          requestedRevision != _localRevision ||
          _unsaved.containsKey(requestedDate)) {
        return;
      }
      if (remote.history.isNotEmpty) {
        _history = List<RoutineDefinition>.of(remote.history);
      }
      _entries = Map<String, RoutineEntry>.of(remote.entries);
      _effectiveScreenTimeMinutes = remote.effectiveScreenTimeMinutes;
      _loadError = null;
    } on Object catch (error) {
      if (reportFailure && requestedDate == _selectedDate) {
        _loadError = error;
      }
    } finally {
      if (showProgress && requestedDate == _selectedDate) {
        _isLoading = false;
        _notify();
      } else if (!showProgress &&
          requestedDate == _selectedDate &&
          requestedRevision == _localRevision) {
        _notify();
      }
    }
  }

  /// Keeps the dashboard aligned with changes coming from the mobile app.
  /// Realtime is immediate; polling is a fallback for suspended browser tabs
  /// and transient websocket interruptions.
  void startAutoRefresh({
    Duration pollingInterval = const Duration(seconds: 30),
  }) {
    _refreshTimer?.cancel();
    _refreshDebounce?.cancel();
    unawaited(_changeSubscription?.cancel());

    if (repository is RoutineChangeFeed) {
      _changeSubscription = (repository as RoutineChangeFeed)
          .watchChanges()
          .listen((_) => _scheduleBackgroundRefresh(), onError: (_) {});
    }
    _refreshTimer = Timer.periodic(
      pollingInterval,
      (_) => unawaited(refreshSilently()),
    );
  }

  void _scheduleBackgroundRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(refreshSilently()),
    );
  }

  Future<void> refreshSilently() async {
    if (_disposed) return;
    if (_backgroundRefreshInFlight) {
      _backgroundRefreshQueued = true;
      return;
    }
    _backgroundRefreshInFlight = true;
    try {
      do {
        _backgroundRefreshQueued = false;
        await flushPendingSaves();
        if (_disposed) return;
        for (final write in List<_RoutineWrite>.of(_unsaved.values)) {
          if (_disposed) return;
          if (identical(_unsaved[write.date], write)) await _save(write);
        }
        if (_disposed) return;
        if (!_unsaved.containsKey(_selectedDate)) {
          await _load(showProgress: false, reportFailure: false);
        }
      } while (_backgroundRefreshQueued && !_disposed);
    } finally {
      _backgroundRefreshInFlight = false;
    }
  }

  Future<void> selectDate(DateTime date) async {
    final normalized = dateOnly(date);
    if (normalized == _selectedDate) return;
    await flushPendingSaves();
    _selectedDate = normalized;
    _localRevision += 1;
    final pending = _unsaved[normalized];
    _entries = pending == null
        ? <String, RoutineEntry>{}
        : Map.of(pending.entries);
    _effectiveScreenTimeMinutes = null;
    _notify();
    if (pending == null) {
      await load();
    } else {
      await refreshSilently();
    }
  }

  Future<void> previousDay() =>
      selectDate(shiftDays(_selectedDate, -1));

  Future<void> nextDay() =>
      selectDate(shiftDays(_selectedDate, 1));

  Future<void> toggleRoutine(String routineId) async {
    final current = entryFor(routineId);
    final nextStatus = current.status == RoutineStatus.ok
        ? RoutineStatus.ko
        : RoutineStatus.ok;
    final clearNutritionDetail =
        routineId == 'alimentazione' && nextStatus != RoutineStatus.ko;
    _entries[routineId] = current.copyWith(
      status: nextStatus,
      completionTimeMinutes: nextStatus == RoutineStatus.ok
          ? _now().hour * 60 + _now().minute
          : null,
      selectedDetailOptionId: clearNutritionDetail
          ? null
          : current.selectedDetailOptionId,
      selectedDetailLabelSnapshot: clearNutritionDetail
          ? null
          : current.selectedDetailLabelSnapshot,
      selectedDetailScoreSnapshot: clearNutritionDetail
          ? null
          : current.selectedDetailScoreSnapshot,
    );
    _localRevision += 1;
    _syncError = null;
    _notify();
    await _enqueueCurrentDaySave();
  }

  /// Imposta lo stato di un'abitudine: fatta, non fatta o da fare.
  Future<void> setStatus(String routineId, RoutineStatus status) async {
    final current = entryFor(routineId);
    final keepDetail = status != RoutineStatus.unmarked;
    _entries[routineId] = RoutineEntry(
      status: status,
      completionTimeMinutes: status == RoutineStatus.ok
          ? current.completionTimeMinutes ?? _now().hour * 60 + _now().minute
          : null,
      selectedDetailOptionId: keepDetail ? current.selectedDetailOptionId : null,
      selectedDetailLabelSnapshot: keepDetail
          ? current.selectedDetailLabelSnapshot
          : null,
      selectedDetailScoreSnapshot: keepDetail
          ? current.selectedDetailScoreSnapshot
          : null,
      notes: current.notes,
    );
    _localRevision += 1;
    _syncError = null;
    _notify();
    await _enqueueCurrentDaySave();
  }

  /// Sceglie (o toglie, con null) il dettaglio di un'abitudine: per esempio
  /// la scheda della palestra o il livello di sgarro.
  Future<void> setDetail(String routineId, RoutineDetailOption? option) async {
    _entries[routineId] = entryFor(routineId).copyWith(
      selectedDetailOptionId: option?.id,
      selectedDetailLabelSnapshot: option?.label,
      selectedDetailScoreSnapshot: option?.score,
    );
    _localRevision += 1;
    _syncError = null;
    _notify();
    await _enqueueCurrentDaySave();
  }

  /// Cambia le opzioni di un'abitudine (per esempio le schede della palestra)
  /// dal giorno mostrato in poi: i giorni passati tengono i nomi di allora.
  Future<void> updateDetailOptions(
    String routineId,
    List<RoutineDetailOption> options,
  ) {
    final index = _history.indexWhere(
      (r) => r.id == routineId && r.isValidOn(_selectedDate),
    );
    if (index < 0) return Future<void>.value();
    final current = _history[index];
    RoutineDefinition copy({DateTime? from, DateTime? until, bool keep = false}) =>
        RoutineDefinition(
          id: current.id,
          name: current.name,
          iconKey: current.iconKey,
          position: current.position,
          weight: current.weight,
          detailOptions: keep ? current.detailOptions : options,
          validFrom: from,
          validUntil: until,
        );
    if (current.validFrom != null && current.validFrom == _selectedDate) {
      _history[index] = copy(from: current.validFrom, until: current.validUntil);
    } else {
      _history[index] = copy(
        from: current.validFrom,
        until: _selectedDate,
        keep: true,
      );
      _history.add(copy(from: _selectedDate, until: current.validUntil));
    }
    // Una scelta che non esiste più resta scritta com'era, senza id.
    final entry = entryFor(routineId);
    if (entry.selectedDetailOptionId != null &&
        !options.any((o) => o.id == entry.selectedDetailOptionId)) {
      _entries[routineId] = entry.copyWith(selectedDetailOptionId: null);
    }
    _localRevision += 1;
    _syncError = null;
    _notify();
    return _enqueueCurrentDaySave();
  }

  /// Aggiunge un'abitudine a partire dal giorno mostrato.
  Future<void> addRoutine({required String name, String iconKey = 'task'}) {
    final clean = name.trim();
    if (clean.isEmpty) return Future<void>.value();
    final active = routines;
    _history.add(
      RoutineDefinition(
        id: 'task_${_now().microsecondsSinceEpoch}',
        name: clean,
        iconKey: iconKey,
        position: active.isEmpty
            ? 0
            : active.map((r) => r.position).reduce((a, b) => a > b ? a : b) + 1,
        validFrom: _selectedDate,
      ),
    );
    _localRevision += 1;
    _syncError = null;
    _notify();
    return _enqueueCurrentDaySave();
  }

  /// Toglie un'abitudine dal giorno mostrato in poi; lo storico resta.
  Future<void> removeRoutine(String routineId) {
    final index = _history.indexWhere(
      (r) => r.id == routineId && r.isValidOn(_selectedDate),
    );
    if (index < 0) return Future<void>.value();
    final current = _history[index];
    if (current.validFrom != null && current.validFrom == _selectedDate) {
      _history.removeAt(index);
    } else {
      _history[index] = RoutineDefinition(
        id: current.id,
        name: current.name,
        iconKey: current.iconKey,
        position: current.position,
        weight: current.weight,
        detailOptions: current.detailOptions,
        validFrom: current.validFrom,
        validUntil: _selectedDate,
      );
    }
    _entries.remove(routineId);
    _localRevision += 1;
    _syncError = null;
    _notify();
    return _enqueueCurrentDaySave();
  }

  Future<void> retrySave() => _enqueueCurrentDaySave();

  Future<void> _enqueueCurrentDaySave() {
    final date = _selectedDate;
    final historySnapshot = List<RoutineDefinition>.of(_history);
    final entriesSnapshot = <String, RoutineEntry>{
      for (final definition in routines) definition.id: entryFor(definition.id),
    };
    final write = _RoutineWrite(date, historySnapshot, entriesSnapshot);
    _unsaved[date] = write;
    return _save(write);
  }

  Future<void> _save(_RoutineWrite write) {
    _pendingSaves += 1;
    _notify();

    final operation = _saveTail.catchError((Object _) {}).then((_) {
      if (!identical(_unsaved[write.date], write)) {
        return Future<void>.value();
      }
      return repository
          .saveDay(
            date: write.date,
            history: write.history,
            entries: write.entries,
          )
          .timeout(const Duration(seconds: 45));
    });
    _saveTail = operation;
    return operation
        .then(
          (_) {
            if (identical(_unsaved[write.date], write)) {
              _unsaved.remove(write.date);
            }
            if (_unsaved.isEmpty) _syncError = null;
          },
          onError: (Object error, StackTrace _) {
            _syncError = error;
          },
        )
        .whenComplete(() {
          _pendingSaves -= 1;
          _notify();
        });
  }

  Future<void> flushPendingSaves() async {
    try {
      await _saveTail;
    } on Object {
      // The sync error remains exposed to the UI and can be retried.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshDebounce?.cancel();
    unawaited(_changeSubscription?.cancel());
    super.dispose();
  }
}

class _RoutineWrite {
  _RoutineWrite(this.date, this.history, this.entries);
  final DateTime date;
  final List<RoutineDefinition> history;
  final Map<String, RoutineEntry> entries;
}
