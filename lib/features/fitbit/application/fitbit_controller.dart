import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../routines/domain/routine.dart';
import '../data/fitbit_repository.dart';
import '../domain/fitbit_day.dart';

class FitbitController extends ChangeNotifier {
  FitbitController({required this.repository, DateTime? initialDate})
    : _selectedDate = dateOnly(initialDate ?? DateTime.now());

  final FitbitRepository repository;
  DateTime _selectedDate;
  FitbitStatus? _status;
  FitbitFailure? _failure;
  bool _loading = false;
  Timer? _timer;
  Timer? _connectionTimer;
  int _connectionPolls = 0;
  bool _disposed = false;
  int _request = 0;
  DateTime? _pendingDate;
  bool _fetching = false;
  bool _saving = false;
  int _writeRevision = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  DateTime get selectedDate => _selectedDate;
  FitbitStatus? get status => _status;
  FitbitDay? get day => _status?.day;
  FitbitFailure? get failure => _failure;
  bool get isLoading => _loading;
  bool get isConfigured => repository.isConfigured;
  bool get isConnected => _status?.isConnected ?? false;

  Future<Uri> beginConnect() async {
    final uri = await repository.beginConnect();
    _connectionTimer?.cancel();
    _connectionPolls = 0;
    _connectionTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _connectionPolls += 1;
      if (isConnected || _connectionPolls >= 200) {
        timer.cancel();
        return;
      }
      unawaited(load());
    });
    return uri;
  }

  Future<void> load({bool background = false}) async {
    if (_disposed || _saving || (_fetching && _pendingDate == _selectedDate)) {
      return;
    }
    if (!isConfigured) {
      _status = null;
      _failure = null;
      _notify();
      return;
    }
    final requested = _selectedDate;
    final request = ++_request;
    final revision = _writeRevision;
    _fetching = true;
    _pendingDate = requested;
    _loading = !background || _status == null;
    _failure = null;
    if (_loading) _notify();
    try {
      final result = await repository
          .fetchDay(requested)
          .timeout(const Duration(seconds: 90));
      if (!_disposed && request == _request && revision == _writeRevision) {
        _status = result;
        if (result.isConnected) _connectionTimer?.cancel();
      }
    } on FitbitFailure catch (error) {
      if (!_disposed && request == _request && revision == _writeRevision) {
        _failure = error;
      }
    } on Object {
      if (!_disposed && request == _request && revision == _writeRevision) {
        _failure = const FitbitFailure(FitbitFailureKind.unavailable);
      }
    } finally {
      if (!_disposed && request == _request) {
        _fetching = false;
        _loading = _saving;
        _notify();
      }
    }
  }

  Future<void> selectDate(DateTime date) async {
    _selectedDate = dateOnly(date);
    _status = null;
    _notify();
    await load();
  }

  Future<void> saveMindfulnessMinutes(int? minutes) async {
    final requested = _selectedDate;
    _saving = true;
    _writeRevision++;
    _loading = true;
    _failure = null;
    _notify();
    try {
      final result = await repository.saveMindfulnessMinutes(
        requested,
        minutes,
      );
      if (!_disposed && _selectedDate == requested) _status = result;
    } on FitbitFailure catch (error) {
      if (_selectedDate == requested) _failure = error;
      rethrow;
    } finally {
      _saving = false;
      if (_selectedDate == requested) {
        _loading = false;
        _notify();
      } else if (!_disposed) {
        unawaited(load());
      }
    }
  }

  void startAutoRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (dateOnly(DateTime.now()) == _selectedDate) {
        unawaited(load(background: true));
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _connectionTimer?.cancel();
    super.dispose();
  }
}
