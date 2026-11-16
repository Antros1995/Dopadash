import 'dart:async';

import '../../calendar/application/calendar_controller.dart';
import '../domain/dashboard_task.dart';
import 'task_controller.dart';

/// Read-only calendar ingestion. Completion belongs to Posta, not Outlook.
class PostaCalendarSync {
  PostaCalendarSync({required this.calendar, required this.tasks});

  final CalendarController calendar;
  final TaskController tasks;
  Timer? _timer;
  Future<void>? _pending;
  bool _disposed = false;

  void start() {
    if (_disposed || _timer != null) return;
    calendar.addListener(_onCalendarDay);
    _onCalendarDay();
    unawaited(sync());
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(sync()),
    );
  }

  void _onCalendarDay() {
    final day = calendar.day;
    if (_disposed ||
        calendar.isLoading ||
        calendar.failure != null ||
        day == null)
      return;
    unawaited(
      tasks.importCalendarDay(day).catchError((Object error) {
        tasks.reportPostaSyncError(error);
      }),
    );
  }

  Future<void> sync() =>
      _pending ??= _sync().whenComplete(() => _pending = null);

  Future<void> _sync() async {
    if (_disposed) return;
    try {
      var date = tasks.postaSyncDate ?? tasks.postaStartDate;
      final today = tasks.today;
      if (date.isBefore(tasks.postaStartDate)) date = tasks.postaStartDate;
      // Re-read the last successful day, then catch up days missed while closed.
      while (!date.isAfter(today) && !_disposed) {
        final day = await calendar.repository.fetchDay(date);
        if (_disposed) return;
        if (day.date != taskDateKey(date))
          throw const FormatException('Giorno calendario non valido');
        await tasks.importCalendarDay(day);
        await tasks.markPostaSynced(date);
        date = DateTime(date.year, date.month, date.day + 1);
      }
      tasks.reportPostaSyncError(null);
    } on Object catch (error) {
      if (!_disposed) tasks.reportPostaSyncError(error);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    calendar.removeListener(_onCalendarDay);
  }
}
