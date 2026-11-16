import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/core/presentation/modular_board.dart';
import 'portfolio_test.dart' show MemoryStore;

class _BuildCounter extends StatelessWidget {
  const _BuildCounter(this.onBuild);
  final VoidCallback onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const Text('Alpha');
  }
}

void main() {
  testWidgets(
    'free drag and resize preserve exact coordinates, neighbours and local persistence',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryStore();
      var builds = 0;
      Widget app(String area) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ModularBoard(
              key: ValueKey(area),
              store: store,
              area: area,
              modules: [
                BoardModule(
                  'a',
                  'A',
                  _BuildCounter(() => builds++),
                  columns: 3,
                  height: 200,
                ),
                const BoardModule(
                  'b',
                  'B',
                  Text('Beta'),
                  columns: 3,
                  height: 200,
                ),
              ],
            ),
          ),
        ),
      );
      Rect rect(String id) {
        final p = tester.widget<Positioned>(
          find.byKey(ValueKey('position-$id')),
        );
        return Rect.fromLTWH(p.left!, p.top!, p.width!, p.height!);
      }

      await tester.pumpWidget(app('one'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('drag-a')), findsNothing);
      await tester.tap(find.text('Modifica layout'));
      await tester.pumpAndSettle();
      final before = rect('a'), neighbour = rect('b'), initialBuilds = builds;
      await tester.drag(
        find.byKey(const ValueKey('drag-a')),
        const Offset(905, 37),
      );
      await tester.pumpAndSettle();
      expect(rect('a').left, closeTo(before.left + 905, .01));
      expect(rect('a').top, closeTo(before.top + 37, .01));
      expect(rect('a').right, closeTo(1196, .01));
      expect(rect('b'), neighbour);
      expect(builds, initialBuilds);
      await tester.drag(
        find.byKey(const ValueKey('resize-b')),
        const Offset(17, 33),
      );
      await tester.pumpAndSettle();
      expect(rect('b').width, closeTo(neighbour.width + 17, .01));
      expect(rect('b').height, closeTo(neighbour.height + 33, .01));
      final savedA = rect('a'), savedB = rect('b');
      await tester.tap(find.text('Salva layout'));
      await tester.pumpAndSettle();
      expect(rect('a'), savedA);
      expect(rect('b'), savedB);
      expect(find.byKey(const ValueKey('resize-a')), findsNothing);
      expect(jsonDecode(store.data.values.single)['version'], 2);
      await tester.pumpWidget(app('two'));
      await tester.pumpAndSettle();
      expect(rect('a').left, 0);
      await tester.pumpWidget(app('one'));
      await tester.pumpAndSettle();
      expect(rect('a'), savedA);
      expect(rect('b'), savedB);
      await tester.tap(find.text('Modifica layout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ripristina layout'));
      await tester.pumpAndSettle();
      expect(store.data, isEmpty);
      expect(rect('a').left, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
