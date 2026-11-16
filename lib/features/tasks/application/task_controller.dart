import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../../core/storage/key_value_store.dart';
import '../../calendar/domain/calendar_event.dart';
import '../data/task_repository.dart';
import '../domain/dashboard_task.dart';

class TaskController extends ChangeNotifier with WidgetsBindingObserver {
  TaskController({
    required this.repository,
    DateTime? initialDate,
    DateTime Function()? now,
    this.cacheStore,
    this.cacheScope = 'local',
  }) : _selectedDate = taskDateOnly(initialDate ?? DateTime.now()),
       _now = now ?? DateTime.now;

  final TaskRepository repository;
  final KeyValueStore? cacheStore;
  final String cacheScope;
  String get _cacheKey => 'dashboard.tasks.cache.v1.$cacheScope';
  final DateTime Function() _now;
  DateTime _selectedDate;
  List<DashboardTask> _tasks = [];
  bool _loading = false;
  Object? _error;
  Future<void> _saveTail = Future<void>.value();
  int _idSequence = 0;
  Timer? _rolloverTimer;
  StreamSubscription<List<DashboardTask>>? _syncSubscription;
  Timer? _retryTimer, _refreshTimer;
  Future<void>? _loadFuture;
  Future<void> _cacheTail = Future<void>.value();
  final Set<String> _pendingDeletes = {};
  final Map<String, DashboardTask> _pendingUpdates = {};
  int _retryAttempt = 0;
  bool _cacheLoaded = false, _disposed = false, _observing = false;
  bool _syncNeedsRestart = true;
  final Set<String> _postaDeletedIds = {};
  bool _postaMigrated = false;
  Future<void>? _postaMigration;
  DateTime? _postaSyncDate;
  Object? _postaSyncError;
  DateTime get postaStartDate => DateTime(2026, 10, 12);
  DateTime? get postaSyncDate => _postaSyncDate;
  Object? get postaSyncError => _postaSyncError;

  // Carry reminders into today's lists without changing their original deadline.
  DateTime dateFor(DashboardTask task) =>
      task.group == DashboardTaskGroup.posta &&
          !task.isCompleted &&
          task.scheduledDate.isBefore(today)
      ? today
      : task.scheduledDate;

  void reportPostaSyncError(Object? error) {
    if (_disposed || identical(error, _postaSyncError)) return;
    _postaSyncError = error;
    _notify();
  }

  Future<void> markPostaSynced(DateTime date) async {
    _postaSyncDate = taskDateOnly(date);
    _writeCache();
    await _cacheTail;
  }

  Future<void> importCalendarDay(CalendarDay day) async {
    await _restoreCache();
    await _migratePosta();
    if (_disposed) return;
    final dayDate = DateTime.tryParse(day.date);
    if (dayDate == null || dayDate.isBefore(postaStartDate)) return;
    var changed = false;
    final byId = {for (final task in _tasks) task.id: task};
    final byEvent = {
      for (final task in _tasks)
        if (task.calendarEventId != null) task.calendarEventId!: task,
    };
    final imports = <DashboardTask>[];
    for (final event in day.events) {
      if (event.isCancelled) continue;
      // The Worker supplies Europe/Rome wall-clock dates; compare calendar days.
      final date = DateTime.tryParse(event.startDateTime);
      if (date == null) continue;
      final due = DateTime(
        date.year,
        date.month,
        date.day,
        date.hour,
        date.minute,
      );
      if (taskDateOnly(due).isBefore(postaStartDate)) continue;
      final id = 'posta-calendar-${base64Url.encode(utf8.encode(event.id))}';
      if (_postaDeletedIds.contains(id)) continue;
      final previous = byEvent[event.id] ?? byId[id];
      if (previous?.isDeleted == true) continue;
      final title = event.subject.trim();
      if (title.isEmpty ||
          (previous?.title == title && previous?.dueAt == due)) {
        continue;
      }
      final task = DashboardTask(
        id: previous?.id ?? id,
        title: title.length > 160 ? title.substring(0, 160) : title,
        group: DashboardTaskGroup.posta,
        color: previous?.color ?? DashboardTaskColor.blue,
        scheduledDate:
            previous != null &&
                previous.scheduledDate != taskDateOnly(previous.deadline)
            ? previous.scheduledDate
            : taskDateOnly(due),
        dueAt: due,
        calendarEventId: event.id,
        createdAt: previous?.createdAt ?? _now(),
        completedAt: previous?.completedAt,
      );
      imports.add(task);
      if (repository is! CalendarPostaRepository) {
        byId[task.id] = task;
        _pendingUpdates[task.id] = task;
      }
      changed = true;
    }
    if (!changed) return;
    if (repository is CalendarPostaRepository) {
      final rows = await (repository as CalendarPostaRepository)
          .importPosta(imports)
          .timeout(const Duration(seconds: 30));
      // Calendar metadata must not replace a user edit queued during the RPC.
      final merged = {
        for (final t in _tasks) t.id: t,
        for (final t in rows) t.id: t,
      };
      merged.addAll(_pendingUpdates);
      _tasks = merged.values.toList();
      _writeCache();
      _notify();
      return;
    }
    _tasks = byId.values.toList();
    _changed();
    await _save();
  }

  Future<void> _migratePosta() {
    if (_postaMigrated) return Future<void>.value();
    return _postaMigration ??= _migratePostaOnce().whenComplete(
      () => _postaMigration = null,
    );
  }

  Future<void> _migratePostaOnce() async {
    if (_postaMigrated) return;
    if (repository is! CalendarPostaRepository) {
      _postaMigrated = true;
      return;
    }
    final legacy = _tasks
        .where((t) => t.group == DashboardTaskGroup.posta)
        .toList();
    final authoritative = await repository.load().timeout(
      const Duration(seconds: 30),
    );
    final serverIds = authoritative.map((t) => t.id).toSet();
    final imports = legacy.where((t) => t.calendarEventId != null).toList();
    for (final id in _postaDeletedIds) {
      final event = legacyPostaEventId(id);
      if (event == null) continue;
      imports.add(
        DashboardTask(
          id: id,
          title: 'Promemoria eliminato',
          group: DashboardTaskGroup.posta,
          color: DashboardTaskColor.blue,
          scheduledDate: postaStartDate,
          createdAt: _now(),
          completedAt: null,
          calendarEventId: event,
          dueAt: postaStartDate,
          deletedAt: _now(),
        ),
      );
    }
    final converted = <DashboardTask>[];
    for (var i = 0; i < imports.length; i += 500) {
      converted.addAll(
        await (repository as CalendarPostaRepository)
            .importPosta(
              imports.sublist(i, (i + 500).clamp(0, imports.length)),
              migrate: true,
            )
            .timeout(const Duration(seconds: 30)),
      );
    }
    final manual = legacy
        .where((t) => t.calendarEventId == null && !serverIds.contains(t.id))
        .toList();
    if (manual.isNotEmpty) {
      if (repository is IncrementalTaskRepository) {
        await (repository as IncrementalTaskRepository)
            .saveUpdates(manual)
            .timeout(const Duration(seconds: 30));
      } else {
        await repository
            .save([...authoritative, ...manual])
            .timeout(const Duration(seconds: 30));
      }
    }
    for (final t in legacy) {
      _pendingUpdates.remove(t.id);
    }
    final merged = {
      for (final t in _tasks.where((t) => t.group != DashboardTaskGroup.posta))
        t.id: t,
      for (final t in authoritative) t.id: t,
      for (final t in converted) t.id: t,
      for (final t in manual) t.id: t,
    };
    merged.addAll(_pendingUpdates);
    _tasks = merged.values.toList();
    _postaDeletedIds.clear();
    _postaSyncDate = null;
    _postaMigrated = true;
    _writeCache();
    await _cacheTail;
    _notify();
  }

  bool get _hasPendingChanges =>
      _pendingUpdates.isNotEmpty || _pendingDeletes.isNotEmpty;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  DateTime get selectedDate => _selectedDate;
  DateTime get today => taskDateOnly(_now());
  bool get isLoading => _loading;
  Object? get error => _error;

  List<DashboardTask> tasksFor(
    DashboardTaskGroup group, {
    bool includeUpcoming = false,
  }) {
    final result = _tasks.where((task) {
      if (task.group != group || task.isDeleted) return false;
      if (task.isCompleted) {
        return taskDateKey(task.completedAt!) == taskDateKey(_selectedDate);
      }
      return includeUpcoming || !task.scheduledDate.isAfter(_selectedDate);
    }).toList();
    result.sort((left, right) {
      if (left.isCompleted != right.isCompleted) {
        return left.isCompleted ? 1 : -1;
      }
      if (group == DashboardTaskGroup.posta) {
        final due = left.deadline.compareTo(right.deadline);
        if (due != 0) return due;
      }
      return left.createdAt.compareTo(right.createdAt);
    });
    return List.unmodifiable(result);
  }

  List<DashboardTask> get overviewTasks {
    final result = _tasks.where((t) => !t.isDeleted).toList();
    result.sort((left, right) {
      if (left.isCompleted != right.isCompleted) {
        return left.isCompleted ? 1 : -1;
      }
      final dateComparison = left.scheduledDate.compareTo(right.scheduledDate);
      if (dateComparison != 0) return dateComparison;
      final due = left.deadline.compareTo(right.deadline);
      if (due != 0) return due;
      return left.createdAt.compareTo(right.createdAt);
    });
    return List.unmodifiable(result);
  }

  Future<void> load({bool background = false}) {
    if (_disposed) return Future<void>.value();
    return _loadFuture ??= _load(
      background: background,
    ).whenComplete(() => _loadFuture = null);
  }

  Future<void> _load({required bool background}) async {
    _loading = !background;
    _notify();
    try {
      await _restoreCache();
      await _saveTail;
      try {
        await _migratePosta();
      } on Object catch (error) {
        reportPostaSyncError(error);
      }
      if (_hasPendingChanges) await _save();
      final tasks = await repository.load().timeout(
        const Duration(seconds: 15),
      );
      if (_disposed) return;
      _receiveTasks(tasks);
    } on Object catch (error) {
      _error = error;
      _scheduleRetry();
    } finally {
      await _startSync();
      _loading = false;
      _notify();
    }
  }

  void selectDate(DateTime date) {
    _selectedDate = taskDateOnly(date);
    notifyListeners();
  }

  void startAutoRollover() {
    _rolloverTimer?.cancel();
    _rolloverTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final today = taskDateOnly(_now());
      final selectedWasPast = _selectedDate.isBefore(today);
      if (selectedWasPast) _selectedDate = today;
      if (selectedWasPast) {
        notifyListeners();
      }
    });
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(load(background: true)),
    );
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(load(background: true));
  }

  Future<void> addTask({
    required String title,
    required DashboardTaskGroup group,
    DashboardTaskColor color = DashboardTaskColor.black,
    DateTime? scheduledDate,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;
    final now = _now();
    _idSequence += 1;
    _tasks.add(
      DashboardTask(
        id: _newTaskId(now),
        title: cleanTitle.length > 160
            ? cleanTitle.substring(0, 160)
            : cleanTitle,
        group: group,
        color: color,
        scheduledDate: taskDateOnly(scheduledDate ?? _selectedDate),
        createdAt: now,
        completedAt: null,
      ),
    );
    _changed(_tasks.last);
    await _save();
  }

  Future<void> toggle(String id) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    final now = _now();
    _tasks[index] = task.isCompleted ? task.reopen() : task.complete(now);
    _changed(_tasks[index]);
    await _save();
  }

  Future<void> setColor(String id, DashboardTaskColor color) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _tasks[index] = _tasks[index].recolor(color);
    _changed(_tasks[index]);
    await _save();
  }

  Future<void> reschedule(String id, DateTime scheduledDate) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    final normalizedDate = taskDateOnly(scheduledDate);
    if (taskDateKey(task.scheduledDate) == taskDateKey(normalizedDate)) return;
    _tasks[index] = task.reschedule(normalizedDate);
    _changed(_tasks[index]);
    await _save();
  }

  Future<void> delete(String id) async {
    final isPosta = _tasks.any(
      (t) => t.id == id && t.group == DashboardTaskGroup.posta,
    );
    if (isPosta && _postaMigrated) {
      final index = _tasks.indexWhere((t) => t.id == id);
      _tasks[index] = _tasks[index].deleted(_now());
      _changed(_tasks[index]);
      await _save();
      return;
    }
    final previousLength = _tasks.length;
    _tasks.removeWhere((task) => task.id == id);
    if (_tasks.length == previousLength) return;
    if (isPosta) {
      _postaDeletedIds.add(id);
    } else {
      _pendingDeletes.add(id);
    }
    _pendingUpdates.remove(id);
    _changed();
    await _save();
    if (isPosta) await _cacheTail;
  }

  void _changed([DashboardTask? task]) {
    if (task != null) _pendingUpdates[task.id] = task;
    _writeCache();
    _notify();
  }

  Future<void> _save() {
    if (!_hasPendingChanges) return _saveTail;
    final snapshot = List<DashboardTask>.of(_tasks);
    final updates = Map<String, DashboardTask>.of(_pendingUpdates);
    final deletions = Set<String>.of(_pendingDeletes);
    _saveTail = _saveTail
        .then((_) async {
          for (final id in deletions) {
            await repository.delete(id).timeout(const Duration(seconds: 15));
          }
          final remoteUpdates = updates.values
              .where(
                (t) => _postaMigrated || t.group != DashboardTaskGroup.posta,
              )
              .toList();
          if (remoteUpdates.isNotEmpty) {
            await (repository is IncrementalTaskRepository
                    ? (repository as IncrementalTaskRepository).saveUpdates(
                        remoteUpdates,
                      )
                    : repository.save(
                        snapshot
                            .where(
                              (t) =>
                                  _postaMigrated ||
                                  t.group != DashboardTaskGroup.posta,
                            )
                            .toList(),
                      ))
                .timeout(const Duration(seconds: 15));
          }
          _pendingDeletes.removeAll(deletions);
          for (final task in remoteUpdates) {
            if (identical(_pendingUpdates[task.id], task)) {
              _pendingUpdates.remove(task.id);
            }
          }
          if (!_hasPendingChanges &&
              (remoteUpdates.isNotEmpty || deletions.isNotEmpty)) {
            _clearError();
          }
          _writeCache();
          _notify();
        })
        .catchError((Object error) {
          _error = error;
          _scheduleRetry();
          _notify();
        });
    return _saveTail;
  }

  Future<void> flushPendingSaves() async {
    await _saveTail;
    await _cacheTail;
  }

  Future<void> _startSync() async {
    if (_disposed || !_syncNeedsRestart) return;
    _syncNeedsRestart = false;
    await _syncSubscription?.cancel();
    if (_disposed) return;
    try {
      _syncSubscription = repository.watch().listen(
        (tasks) {
          if (_disposed) return;
          _receiveTasks(tasks);
        },
        onError: (Object error) {
          if (_disposed) return;
          _error = error;
          _syncNeedsRestart = true;
          _scheduleRetry();
          _notify();
        },
        onDone: () => _syncNeedsRestart = true,
      );
    } on Object catch (error) {
      _error = error;
      _syncNeedsRestart = true;
      _scheduleRetry();
    }
  }

  void _receiveTasks(List<DashboardTask> tasks) {
    final merged = {
      if (!_postaMigrated)
        for (final task in _tasks.where(
          (t) => t.group == DashboardTaskGroup.posta,
        ))
          task.id: task,
      for (final task in tasks) task.id: task,
    };
    for (final id in _pendingDeletes) {
      merged.remove(id);
    }
    merged.addAll(_pendingUpdates);
    _tasks = merged.values.toList();
    if (!_hasPendingChanges) _clearError();
    _writeCache();
    _notify();
  }

  void _clearError() {
    _error = null;
    _retryAttempt = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) return;
    final delay = [3, 6, 12, 30][_retryAttempt.clamp(0, 3)];
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: delay), () {
      _retryTimer = null;
      unawaited(load(background: true));
    });
  }

  Future<void> _restoreCache() async {
    if (_cacheLoaded || cacheStore == null) return;
    _cacheLoaded = true;
    try {
      final raw = await cacheStore!.read(_cacheKey);
      if (raw == null || _disposed || _hasPendingChanges) return;
      final data = jsonDecode(raw) as Map;
      _postaMigrated = data['postaCloudMigrated'] == true;
      _postaDeletedIds.addAll(List<String>.from(data['postaDeletedIds'] ?? []));
      _postaSyncDate = DateTime.tryParse(
        data['postaSyncDate'] as String? ?? '',
      );
      _tasks = [
        for (final row in data['tasks'])
          DashboardTask.fromJson(Map<String, Object?>.from(row)),
      ];
      _pendingDeletes.addAll(List<String>.from(data['deletions'] ?? []));
      if (data['pending'] == true) {
        final updates = data['updates'];
        final pending = updates is List
            ? [
                for (final row in updates)
                  DashboardTask.fromJson(Map<String, Object?>.from(row)),
              ]
            : _tasks;
        _pendingUpdates.addAll({for (final task in pending) task.id: task});
      }
      _notify();
    } on Object {
      // A damaged local cache must not prevent the authoritative remote load.
    }
  }

  void _writeCache() {
    if (_disposed || cacheStore == null) return;
    final value = jsonEncode({
      'tasks': [for (final task in _tasks) task.toJson()],
      'pending': _hasPendingChanges,
      'updates': [for (final task in _pendingUpdates.values) task.toJson()],
      'deletions': _pendingDeletes.toList(),
      'postaDeletedIds': _postaDeletedIds.toList(),
      'postaCloudMigrated': _postaMigrated,
      'postaSyncDate': _postaSyncDate == null
          ? null
          : taskDateKey(_postaSyncDate!),
    });
    _cacheTail = _cacheTail
        .then((_) => cacheStore!.write(_cacheKey, value))
        .catchError((Object _) {});
  }

  String _newTaskId(DateTime now) {
    // A UUID-shaped client id lets Supabase upsert the same task after a retry.
    final time = now.microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0');
    final sequence = (++_idSequence).toRadixString(16).padLeft(16, '0');
    return '${time.substring(0, 8)}-${time.substring(8, 12)}-4${time.substring(13, 16)}-8${sequence.substring(1, 4)}-${sequence.substring(4)}';
  }

  @override
  void dispose() {
    _disposed = true;
    _rolloverTimer?.cancel();
    _refreshTimer?.cancel();
    _retryTimer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    unawaited(_syncSubscription?.cancel());
    super.dispose();
  }
}
