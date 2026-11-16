import 'package:flutter/foundation.dart';

import '../../routines/domain/routine.dart';
import '../data/calendar_repository.dart';
import '../domain/calendar_event.dart';

class CalendarController extends ChangeNotifier {
  CalendarController({required this.repository, DateTime? initialDate})
    : _selectedDate = dateOnly(initialDate ?? DateTime.now());

  final CalendarRepository repository;
  DateTime _selectedDate;
  CalendarDay? _day;
  CalendarFailure? _failure;
  bool _isLoading = false;
  bool _disposed = false, _fetching = false;
  int _request = 0;
  DateTime? _pendingDate;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get isConfigured => repository.isConfigured;
  bool get isLoading => _isLoading;
  DateTime get selectedDate => _selectedDate;
  CalendarDay? get day => _day;
  CalendarFailure? get failure => _failure;
  List<CalendarEvent> get events => _day?.events ?? const [];

  Future<Uri> beginOutlookConnect() => repository.beginOutlookConnect();

  Future<void> load({bool background = false}) async {
    if (_disposed || (_fetching && _pendingDate == _selectedDate)) return;
    if (!isConfigured) {
      _day = null;
      _failure = null;
      _notify();
      return;
    }
    final requestedDate = _selectedDate;
    final request = ++_request;
    _fetching = true;
    _pendingDate = requestedDate;
    _isLoading = !background || _day == null;
    _failure = null;
    if (_isLoading) _notify();
    try {
      final day = await repository
          .fetchDay(requestedDate)
          .timeout(const Duration(seconds: 90));
      if (!_disposed && request == _request) _day = day;
    } on CalendarFailure catch (error) {
      if (!_disposed && request == _request) {
        if (!background) _day = null;
        _failure = error;
      }
    } on Object {
      if (!_disposed && request == _request) {
        if (!background) _day = null;
        _failure = const CalendarFailure(CalendarFailureKind.unavailable);
      }
    } finally {
      if (!_disposed && request == _request) {
        _fetching = false;
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> selectDate(DateTime date) async {
    _selectedDate = dateOnly(date);
    _day = null;
    _notify();
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
