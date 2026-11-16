import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/application/task_controller.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/data/task_repository.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/domain/dashboard_task.dart';

void main() {
  test(
    'unfinished tasks roll forward and completed tasks move to the bottom',
    () async {
      final repository = _MemoryTaskRepository([
        DashboardTask(
          id: 'old',
          title: 'Da recuperare',
          group: DashboardTaskGroup.personal,
          color: DashboardTaskColor.red,
          scheduledDate: DateTime(2026, 8, 25),
          createdAt: DateTime(2026, 8, 25, 8),
          completedAt: null,
        ),
      ]);
      final controller = TaskController(
        repository: repository,
        initialDate: DateTime(2026, 8, 30),
        now: () => DateTime(2026, 8, 30, 9),
      );

      await controller.load();
      await controller.addTask(
        title: 'Nuovo',
        group: DashboardTaskGroup.personal,
        color: DashboardTaskColor.blue,
        scheduledDate: DateTime(2026, 8, 30),
      );

      expect(
        controller
            .tasksFor(DashboardTaskGroup.personal)
            .map((task) => task.title),
        ['Da recuperare', 'Nuovo'],
      );
      expect(
        controller.overviewTasks.first.scheduledDate,
        DateTime(2026, 8, 25),
      );
      expect(
        controller.overviewTasks
            .firstWhere((task) => task.title == 'Nuovo')
            .scheduledDate,
        DateTime(2026, 8, 30),
      );

      await controller.toggle('old');
      final sorted = controller.tasksFor(DashboardTaskGroup.personal);
      expect(sorted.last.title, 'Da recuperare');
      expect(sorted.last.isCompleted, isTrue);
      expect(
        repository.values.firstWhere((task) => task.id == 'old').color,
        DashboardTaskColor.red,
      );
      expect(
        repository.values.firstWhere((task) => task.id == 'old').scheduledDate,
        DateTime(2026, 8, 25),
      );

      controller.selectDate(DateTime(2026, 8, 31));
      expect(
        controller
            .tasksFor(DashboardTaskGroup.personal)
            .map((task) => task.title),
        ['Nuovo'],
      );

      await controller.delete('old');
      expect(
        controller
            .tasksFor(DashboardTaskGroup.personal)
            .map((task) => task.title),
        ['Nuovo'],
      );
      expect(repository.values.any((task) => task.id == 'old'), isFalse);
    },
  );

  test('reschedules an existing task and persists the new date', () async {
    final repository = _MemoryTaskRepository([
      DashboardTask(
        id: 'task-1',
        title: 'Sposta appuntamento',
        group: DashboardTaskGroup.work,
        color: DashboardTaskColor.blue,
        scheduledDate: DateTime(2026, 9, 8),
        createdAt: DateTime(2026, 9, 8, 8),
        completedAt: null,
      ),
    ]);
    final controller = TaskController(
      repository: repository,
      initialDate: DateTime(2026, 9, 8),
    );

    await controller.load();
    await controller.reschedule('task-1', DateTime(2026, 9, 14, 18));

    expect(
      controller.overviewTasks.single.scheduledDate,
      DateTime(2026, 9, 14),
    );
    expect(repository.values.single.scheduledDate, DateTime(2026, 9, 14));
  });
}

class _MemoryTaskRepository implements TaskRepository {
  _MemoryTaskRepository(this.values);
  List<DashboardTask> values;

  @override
  Future<List<DashboardTask>> load() async => List.of(values);

  @override
  Stream<List<DashboardTask>> watch() => const Stream.empty();

  @override
  Future<void> save(List<DashboardTask> tasks) async {
    values = List.of(tasks);
  }

  @override
  Future<void> delete(String id) async {
    values.removeWhere((task) => task.id == id);
  }
}
