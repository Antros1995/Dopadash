import 'dart:async';
import 'dart:convert';

import 'package:supabase/supabase.dart';

import '../../../core/storage/key_value_store.dart';
import '../domain/dashboard_task.dart';

abstract interface class TaskRepository {
  Future<List<DashboardTask>> load();
  Stream<List<DashboardTask>> watch();
  Future<void> save(List<DashboardTask> tasks);
  Future<void> delete(String id);
}

/// Remote stores can update only edited tasks without overwriting other clients.
abstract interface class IncrementalTaskRepository {
  Future<void> saveUpdates(List<DashboardTask> tasks);
}

abstract interface class CalendarPostaRepository {
  Future<List<DashboardTask>> importPosta(
    List<DashboardTask> tasks, {
    bool migrate = false,
  });
}

class LocalTaskRepository implements TaskRepository {
  LocalTaskRepository(this._store, {required String userId})
    : _storageKey = 'dashboard_tasks_v1_$userId';

  final KeyValueStore _store;
  final String _storageKey;

  @override
  Future<List<DashboardTask>> load() async {
    final raw = await _store.read(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final tasks = <DashboardTask>[];
      for (final item in decoded.take(500)) {
        if (item is! Map) continue;
        try {
          tasks.add(DashboardTask.fromJson(Map<String, Object?>.from(item)));
        } on Object {
          // A malformed task must not hide the remaining saved tasks.
        }
      }
      return tasks;
    } on FormatException {
      return const [];
    }
  }

  @override
  Stream<List<DashboardTask>> watch() => const Stream.empty();

  @override
  Future<void> save(List<DashboardTask> tasks) => _store.write(
    _storageKey,
    jsonEncode([for (final task in tasks) task.toJson()]),
  );

  @override
  Future<void> delete(String id) async {
    final tasks = await load();
    await save(tasks.where((task) => task.id != id).toList());
  }
}

class SupabaseTaskRepository
    implements
        TaskRepository,
        IncrementalTaskRepository,
        CalendarPostaRepository {
  SupabaseTaskRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw StateError('Sessione non disponibile.');
    }
    return userId;
  }

  @override
  Future<List<DashboardTask>> load() async {
    final rows = await _client
        .from('monitoraggio_personale_tasks')
        .select()
        .eq('user_id', _userId)
        .order('created_at');
    return (rows as List<dynamic>)
        .whereType<Map>()
        .map(
          (row) => DashboardTask.fromRemoteJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  @override
  Stream<List<DashboardTask>> watch() => _client
      .from('monitoraggio_personale_tasks')
      .stream(primaryKey: ['id'])
      .eq('user_id', _userId)
      .order('created_at')
      .map(
        (rows) => rows
            .map((row) => DashboardTask.fromRemoteJson(row))
            .toList(growable: false),
      );

  @override
  Future<void> save(List<DashboardTask> tasks) async {
    if (tasks.isEmpty) return;
    await _client.from('monitoraggio_personale_tasks').upsert([
      for (final task in tasks) task.toRemoteJson(_userId),
    ], onConflict: 'id');
  }

  @override
  Future<void> saveUpdates(List<DashboardTask> tasks) => save(tasks);

  @override
  Future<List<DashboardTask>> importPosta(
    List<DashboardTask> tasks, {
    bool migrate = false,
  }) async {
    if (tasks.isEmpty) return const [];
    final result = await _client.rpc(
      'monitoraggio_personale_import_posta',
      params: {
        'p_tasks': [for (final t in tasks) t.toRemoteJson(_userId)],
        'p_migrate': migrate,
      },
    );
    return (result as List)
        .map(
          (row) => DashboardTask.fromRemoteJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> delete(String id) => _client
      .from('monitoraggio_personale_tasks')
      .delete()
      .eq('id', id)
      .eq('user_id', _userId);
}
