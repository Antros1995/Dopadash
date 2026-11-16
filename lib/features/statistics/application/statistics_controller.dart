import 'package:flutter/material.dart';

import '../../routines/data/routine_repository.dart';
import '../../routines/domain/routine.dart';
import '../domain/routine_statistics.dart';

class StatisticsController extends ChangeNotifier {
  StatisticsController({
    required this.repository,
    required List<RoutineDefinition> history,
    DateTime? initialDate,
    DateTime Function()? now,
  }) : _history = List.of(history),
       _anchor = dateOnly(initialDate ?? DateTime.now()),
       _now = now ?? DateTime.now {
    _routineId = routineOptions.firstOrNull?.id;
  }

  final RoutineRepository repository;
  final DateTime Function() _now;
  List<RoutineDefinition> _history;
  DateTime _anchor;
  StatisticsPeriod _period = StatisticsPeriod.month;
  StatisticsRange? _customRange;
  String? _routineId;
  RoutineStatistics? _current;
  RoutineStatistics? _previous;
  bool _isLoading = false;
  Object? _error;
  int _requestVersion = 0;

  DateTime get anchor => _anchor;
  StatisticsPeriod get period => _period;
  StatisticsRange? get customRange => _customRange;
  String? get routineId => _routineId;
  RoutineStatistics? get current => _current;
  RoutineStatistics? get previous => _previous;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  List<RoutineDefinition> get routineOptions {
    final byId = <String, RoutineDefinition>{};
    final sorted = List<RoutineDefinition>.of(_history)
      ..sort((left, right) {
        final leftDate = left.validFrom ?? DateTime(1970);
        final rightDate = right.validFrom ?? DateTime(1970);
        return leftDate.compareTo(rightDate);
      });
    for (final definition in sorted) {
      byId[definition.id] = definition;
    }
    final values = byId.values.toList()
      ..sort((left, right) => left.position.compareTo(right.position));
    return List.unmodifiable(values);
  }

  StatisticsRange get range {
    final selected = statisticsRangeFor(
      _period,
      _anchor,
      customRange: _customRange,
    );
    final tomorrow = dateOnly(_now()).add(const Duration(days: 1));
    if (selected.start.isBefore(tomorrow) &&
        selected.endExclusive.isAfter(tomorrow)) {
      return StatisticsRange(start: selected.start, endExclusive: tomorrow);
    }
    return selected;
  }

  void updateHistory(List<RoutineDefinition> history) {
    _history = List.of(history);
    if (!routineOptions.any((option) => option.id == _routineId)) {
      _routineId = routineOptions.firstOrNull?.id;
    }
  }

  Future<void> setRoutine(String? id) async {
    if (id == null || id == _routineId) return;
    _routineId = id;
    notifyListeners();
    await load();
  }

  Future<void> setPeriod(StatisticsPeriod period) async {
    if (period == _period) return;
    _period = period;
    notifyListeners();
    if (period != StatisticsPeriod.custom || _customRange != null) await load();
  }

  Future<void> setAnchor(DateTime value) async {
    _anchor = dateOnly(value);
    notifyListeners();
    await load();
  }

  Future<void> setCustomRange(DateTimeRange value) async {
    _customRange = StatisticsRange(
      start: dateOnly(value.start),
      endExclusive: dateOnly(value.end).add(const Duration(days: 1)),
    );
    _period = StatisticsPeriod.custom;
    notifyListeners();
    await load();
  }

  Future<void> load() async {
    final id = _routineId;
    if (id == null) return;
    final request = ++_requestVersion;
    final selectedRange = range;
    final previousRange = _comparisonRange(selectedRange);
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final entries = await repository.fetchEntries(
        start: previousRange.start,
        endExclusive: selectedRange.endExclusive,
      );
      if (request != _requestVersion) return;
      _current = calculateRoutineStatistics(
        routineId: id,
        range: selectedRange,
        history: _history,
        entries: entries,
      );
      _previous = calculateRoutineStatistics(
        routineId: id,
        range: previousRange,
        history: _history,
        entries: entries,
      );
    } on Object catch (error) {
      if (request == _requestVersion) _error = error;
    } finally {
      if (request == _requestVersion) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  StatisticsRange _comparisonRange(StatisticsRange current) {
    switch (_period) {
      case StatisticsPeriod.week:
        return StatisticsRange(
          start: current.start.subtract(const Duration(days: 7)),
          endExclusive: current.endExclusive.subtract(const Duration(days: 7)),
        );
      case StatisticsPeriod.month:
        final start = DateTime(current.start.year, current.start.month - 1);
        final limit = DateTime(current.start.year, current.start.month);
        final desired = start.add(Duration(days: current.days));
        return StatisticsRange(
          start: start,
          endExclusive: desired.isAfter(limit) ? limit : desired,
        );
      case StatisticsPeriod.year:
        final start = DateTime(current.start.year - 1);
        final limit = DateTime(current.start.year);
        final desired = start.add(Duration(days: current.days));
        return StatisticsRange(
          start: start,
          endExclusive: desired.isAfter(limit) ? limit : desired,
        );
      case StatisticsPeriod.custom:
        return current.previous;
    }
  }
}
