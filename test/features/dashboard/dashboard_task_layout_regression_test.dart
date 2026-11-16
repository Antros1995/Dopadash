import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/core/presentation/app_card.dart';
import 'package:monitoraggio_personale_desktop/core/presentation/modular_board.dart';
import 'package:monitoraggio_personale_desktop/core/storage/key_value_store.dart';
import 'package:monitoraggio_personale_desktop/features/dashboard/presentation/widgets/home_components.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/application/task_controller.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/data/task_repository.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/domain/dashboard_task.dart';

class _Store implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

class _Tasks implements TaskRepository, IncrementalTaskRepository {
  final events = StreamController<List<DashboardTask>>.broadcast();
  List<DashboardTask> values = [];
  bool failLoad = false, failSave = false;
  @override
  Future<List<DashboardTask>> load() async {
    if (failLoad) throw StateError('offline');
    return List.of(values);
  }

  @override
  Stream<List<DashboardTask>> watch() => events.stream;
  @override
  Future<void> save(List<DashboardTask> tasks) => saveUpdates(tasks);
  @override
  Future<void> saveUpdates(List<DashboardTask> tasks) async {
    if (failSave) throw StateError('offline');
    final merged = {for (final task in values) task.id: task};
    merged.addAll({for (final task in tasks) task.id: task});
    values = merged.values.toList();
  }

  @override
  Future<void> delete(String id) async =>
      values.removeWhere((task) => task.id == id);
}

DashboardTask _task(
  String id, {
  DashboardTaskGroup group = DashboardTaskGroup.personal,
}) => DashboardTask(
  id: id,
  title: id,
  group: group,
  color: DashboardTaskColor.blue,
  scheduledDate: DateTime(2026, 10, 15),
  createdAt: DateTime(2026, 10, 8),
  completedAt: null,
);

Rect _rect(WidgetTester tester, String id) {
  final p = tester.widget<Positioned>(find.byKey(ValueKey('position-$id')));
  return Rect.fromLTWH(p.left!, p.top!, p.width!, p.height!);
}

void main() {
  testWidgets(
    'drag and resize push colliding cards down and restore exact repaired layout',
    (tester) async {
      final store = _Store();
      Widget app() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ModularBoard(
              area: 'collision',
              store: store,
              modules: const [
                BoardModule(
                  'a',
                  'A',
                  Text('Alpha'),
                  height: 180,
                  minHeight: 120,
                ),
                BoardModule(
                  'b',
                  'B',
                  Text('Beta'),
                  height: 180,
                  minHeight: 120,
                ),
                BoardModule(
                  'c',
                  'C',
                  Text('Gamma'),
                  height: 180,
                  minHeight: 120,
                ),
              ],
            ),
          ),
        ),
      );
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifica layout'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('drag-a')),
        const Offset(0, 150),
      );
      await tester.pumpAndSettle();
      expect(_rect(tester, 'a').top, 150);
      expect(
        _rect(tester, 'b').top,
        greaterThanOrEqualTo(_rect(tester, 'a').bottom + 12),
      );
      await tester.drag(
        find.byKey(const ValueKey('resize-a')),
        const Offset(0, 190),
      );
      await tester.pumpAndSettle();
      final saved = {
        for (final id in ['a', 'b', 'c']) id: _rect(tester, id),
      };
      expect(saved['b']!.overlaps(saved['a']!), isFalse);
      expect(saved['c']!.overlaps(saved['b']!), isFalse);
      await tester.tap(find.text('Salva layout'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      for (final id in saved.keys) {
        expect(_rect(tester, id), saved[id]);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all three previews scroll every task and grow their real viewport on resize',
    (tester) async {
      final repo = _Tasks()
        ..values = [
          for (final group in DashboardTaskGroup.values)
            for (var i = 0; i < 10; i++)
              _task('${group.name} $i', group: group),
        ];
      final controller = TaskController(
        repository: repo,
        initialDate: DateTime(2026, 10, 8),
      );
      addTearDown(controller.dispose);
      addTearDown(repo.events.close);
      await controller.load();
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModularBoard(
                area: 'tasks',
                store: _Store(),
                modules: [
                  for (final group in DashboardTaskGroup.values)
                    BoardModule(
                      group.name,
                      group.name,
                      HomeTaskPreview(
                        key: ValueKey('preview-${group.name}'),
                        title: group.name,
                        group: group,
                        controller: controller,
                        onOpen: () {},
                      ),
                      columns: 4,
                      height: 160,
                      minHeight: 120,
                      scroll: false,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder preview(DashboardTaskGroup group) =>
          find.byKey(ValueKey('preview-${group.name}'));
      for (final group in DashboardTaskGroup.values) {
        final list = tester.widget<ListView>(
          find.descendant(of: preview(group), matching: find.byType(ListView)),
        );
        expect(
          (list.childrenDelegate as SliverChildBuilderDelegate).childCount,
          10,
        );
        expect(
          find.descendant(of: preview(group), matching: find.byType(Scrollbar)),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('${group.name} 9'),
          80,
          scrollable: find.descendant(
            of: preview(group),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('${group.name} 9'), findsOneWidget);
      }
      final listFinder = find.descendant(
        of: preview(DashboardTaskGroup.personal),
        matching: find.byType(ListView),
      );
      final before = tester.getSize(listFinder).height;
      await tester.tap(find.text('Modifica layout'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('resize-personal')),
        const Offset(0, 240),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva layout'));
      await tester.pumpAndSettle();
      expect(tester.getSize(listFinder).height, closeTo(before + 240, .01));
      final card = find.descendant(
        of: preview(DashboardTaskGroup.personal),
        matching: find.byType(AppCard),
      );
      expect(tester.getSize(card).height, _rect(tester, 'personal').height);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cached activities recover automatically and remote changes preserve pending edits',
    (tester) async {
      final store = _Store();
      final cached = _task('cached');
      store.values['dashboard.tasks.cache.v1.owner'] = jsonEncode({
        'tasks': [cached.toJson()],
      });
      final repo = _Tasks()..failLoad = true;
      final controller = TaskController(
        repository: repo,
        cacheStore: store,
        cacheScope: 'owner',
      );
      addTearDown(controller.dispose);
      addTearDown(repo.events.close);
      await controller.load();
      expect(controller.overviewTasks.single.id, 'cached');
      expect(controller.error, isNotNull);
      repo.failLoad = false;
      repo.values = [cached, _task('remote')];
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(controller.overviewTasks.length, 2);
      expect(controller.error, isNull);
      repo.failSave = true;
      await controller.toggle('cached');
      repo.values = [cached, _task('remote'), _task('new from phone')];
      repo.events.add(repo.values);
      await tester.pump();
      expect(
        controller.overviewTasks
            .firstWhere((task) => task.id == 'cached')
            .isCompleted,
        isTrue,
      );
      expect(controller.overviewTasks.length, 3);
      repo.failSave = false;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
        repo.values.firstWhere((task) => task.id == 'cached').isCompleted,
        isTrue,
      );
      expect(repo.values.any((task) => task.id == 'new from phone'), isTrue);
      expect(controller.error, isNull);
      await controller.flushPendingSaves();
    },
  );
}
