import 'dart:convert';

String? legacyPostaEventId(String id) {
  const prefix = 'posta-calendar-';
  if (!id.startsWith(prefix)) return null;
  try {
    return utf8.decode(base64Url.decode(id.substring(prefix.length)));
  } on Object {
    return null;
  }
}

enum DashboardTaskGroup { personal, work, personalWork, posta }

DashboardTaskGroup dashboardTaskGroupFromStorage(Object? value) =>
    switch (value) {
      'work' => DashboardTaskGroup.work,
      'personal_work' => DashboardTaskGroup.personalWork,
      'posta' => DashboardTaskGroup.posta,
      _ => DashboardTaskGroup.personal,
    };

String dashboardTaskGroupStorageValue(DashboardTaskGroup value) =>
    switch (value) {
      DashboardTaskGroup.personal => 'personal',
      DashboardTaskGroup.work => 'work',
      DashboardTaskGroup.personalWork => 'personal_work',
      DashboardTaskGroup.posta => 'posta',
    };

enum DashboardTaskColor { black, red, blue, green, yellow }

class DashboardTask {
  const DashboardTask({
    required this.id,
    required this.title,
    required this.group,
    required this.color,
    required this.scheduledDate,
    required this.createdAt,
    required this.completedAt,
    this.dueAt,
    this.calendarEventId,
    this.deletedAt,
  });

  factory DashboardTask.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    final scheduledDate = json['scheduledDate'];
    final createdAt = json['createdAt'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        scheduledDate is! String ||
        createdAt is! String) {
      throw const FormatException('Task non valido');
    }
    return DashboardTask(
      id: id,
      title: title.trim(),
      group: dashboardTaskGroupFromStorage(json['group']),
      color: DashboardTaskColor.values.firstWhere(
        (value) => value.name == json['color'],
        orElse: () => DashboardTaskColor.black,
      ),
      scheduledDate: DateTime.parse(scheduledDate),
      createdAt: DateTime.parse(createdAt),
      dueAt: json['dueAt'] is String
          ? DateTime.tryParse(json['dueAt']! as String)
          : null,
      calendarEventId:
          json['calendarEventId'] as String? ?? legacyPostaEventId(id),
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
      completedAt: json['completedAt'] is String
          ? DateTime.tryParse(json['completedAt']! as String)
          : null,
    );
  }

  factory DashboardTask.fromRemoteJson(Map<String, dynamic> json) =>
      DashboardTask(
        id: json['id'] as String,
        title: (json['title'] as String).trim(),
        group: dashboardTaskGroupFromStorage(json['task_group']),
        color: DashboardTaskColor.values.firstWhere(
          (value) => value.name == json['color'],
          orElse: () => DashboardTaskColor.black,
        ),
        scheduledDate: DateTime.parse(json['scheduled_date'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        dueAt: DateTime.tryParse(json['due_at'] as String? ?? ''),
        calendarEventId: json['calendar_event_id'] as String?,
        deletedAt: DateTime.tryParse(json['deleted_at'] as String? ?? ''),
        completedAt: json['completed_at'] is String
            ? DateTime.tryParse(json['completed_at'] as String)
            : null,
      );

  final String id;
  final String title;
  final DashboardTaskGroup group;
  final DashboardTaskColor color;
  final DateTime scheduledDate;
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? dueAt;
  final String? calendarEventId;
  final DateTime? deletedAt;
  bool get isDeleted => deletedAt != null;
  DateTime get deadline => dueAt ?? scheduledDate;

  bool get isCompleted => completedAt != null;

  DashboardTask complete(DateTime when) => DashboardTask(
    id: id,
    title: title,
    group: group,
    color: color,
    scheduledDate: scheduledDate,
    createdAt: createdAt,
    completedAt: when,
    dueAt: dueAt,
    calendarEventId: calendarEventId,
    deletedAt: deletedAt,
  );

  DashboardTask reopen() => DashboardTask(
    id: id,
    title: title,
    group: group,
    color: color,
    scheduledDate: scheduledDate,
    createdAt: createdAt,
    completedAt: null,
    dueAt: dueAt,
    calendarEventId: calendarEventId,
    deletedAt: deletedAt,
  );

  DashboardTask recolor(DashboardTaskColor nextColor) => DashboardTask(
    id: id,
    title: title,
    group: group,
    color: nextColor,
    scheduledDate: scheduledDate,
    createdAt: createdAt,
    completedAt: completedAt,
    dueAt: dueAt,
    calendarEventId: calendarEventId,
    deletedAt: deletedAt,
  );

  DashboardTask reschedule(DateTime nextDate) => DashboardTask(
    id: id,
    title: title,
    group: group,
    color: color,
    scheduledDate: taskDateOnly(nextDate),
    createdAt: createdAt,
    completedAt: completedAt,
    dueAt: dueAt,
    calendarEventId: calendarEventId,
    deletedAt: deletedAt,
  );

  DashboardTask deleted(DateTime when) => DashboardTask(
    id: id,
    title: title,
    group: group,
    color: color,
    scheduledDate: scheduledDate,
    createdAt: createdAt,
    completedAt: completedAt,
    dueAt: dueAt,
    calendarEventId: calendarEventId,
    deletedAt: when,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'group': dashboardTaskGroupStorageValue(group),
    'color': color.name,
    'scheduledDate': taskDateKey(scheduledDate),
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'dueAt': dueAt?.toIso8601String(),
    'calendarEventId': calendarEventId,
    'deletedAt': deletedAt?.toIso8601String(),
  };

  Map<String, Object?> toRemoteJson(String userId) => {
    'id': id,
    'user_id': userId,
    'title': title,
    'task_group': dashboardTaskGroupStorageValue(group),
    'color': color.name,
    'scheduled_date': taskDateKey(scheduledDate),
    'completed_at': completedAt?.toIso8601String(),
    'source': 'desktop',
    if (group == DashboardTaskGroup.posta) ...{
      'due_at': dueAt?.toIso8601String(),
      'calendar_event_id': calendarEventId,
      'deleted_at': deletedAt?.toIso8601String(),
    },
  };
}

DateTime taskDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String taskDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
