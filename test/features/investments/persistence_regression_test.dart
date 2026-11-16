import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/core/presentation/modular_board.dart';
import 'package:monitoraggio_personale_desktop/core/presentation/app_card.dart';
import 'package:monitoraggio_personale_desktop/features/markets/presentation/finance_widgets.dart';
import 'portfolio_test.dart' show MemoryStore;

class DelayedStore extends MemoryStore {
  final gate = Completer<void>();
  int writes = 0;
  @override
  Future<String?> read(String key) async {
    await gate.future;
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    await super.write(key, value);
  }
}

Rect rect(WidgetTester tester, String id) {
  final p = tester.widget<Positioned>(find.byKey(ValueKey('position-$id')));
  return Rect.fromLTWH(p.left!, p.top!, p.width!, p.height!);
}

void main() {
  testWidgets(
    'regression: restore before layout, retain absent IDs, exact geometry at the saved width and proportional width on resize',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = DelayedStore();
      const key = 'dashboard.layout.v1.local.one';
      store.data[key] = jsonEncode({
        'version': 2,
        'width': 1200,
        'rects': {
          'a': [13.25, 20.5, 321.75, 240.5],
          'b': [770.5, 110, 330, 215],
        },
      });
      Widget app(String area, bool showB) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ModularBoard(
              area: area,
              store: store,
              modules: [
                const BoardModule('a', 'A', AppCard(child: Text('Alpha'))),
                if (showB)
                  const BoardModule('b', 'B', AppCard(child: Text('Beta'))),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(app('one', false));
      expect(find.byKey(const ValueKey('position-a')), findsNothing);
      store.gate.complete();
      await tester.pumpAndSettle();
      const a = Rect.fromLTWH(13.25, 20.5, 321.75, 240.5),
          b = Rect.fromLTWH(770.5, 110, 330, 215);
      expect(rect(tester, 'a'), a);
      await tester.pumpWidget(app('one', true));
      await tester.pumpAndSettle();
      expect(rect(tester, 'b'), b);
      // Su uno schermo diverso le schede si riproporzionano in larghezza.
      void expectScaled(String id, Rect saved) {
        const k = 1000 / 1200;
        final shown = rect(tester, id);
        expect(shown.left, closeTo(saved.left * k, .01));
        expect(shown.width, closeTo(saved.width * k, .01));
        expect(shown.top, saved.top);
        expect(shown.height, saved.height);
      }

      tester.view.physicalSize = const Size(1000, 900);
      await tester.pumpAndSettle();
      expectScaled('a', a);
      expectScaled('b', b);
      expect(store.writes, 0);
      await tester.pumpWidget(app('two', true));
      await tester.pumpAndSettle();
      expect(rect(tester, 'a').left, 0);
      await tester.pumpWidget(app('one', true));
      await tester.pumpAndSettle();
      expectScaled('a', a);
      expectScaled('b', b);
      expect(store.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'regression: gesture end saves without button and white cards fill resized viewport',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryStore();
      Widget app() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ModularBoard(
              area: 'one',
              store: store,
              modules: const [
                BoardModule(
                  'a',
                  'A',
                  AppCard(key: ValueKey('white-a'), child: Text('Alpha')),
                  columns: 4,
                  height: 200,
                ),
                BoardModule(
                  'b',
                  'B',
                  FinanceCard(
                    key: ValueKey('white-b'),
                    title: 'Investimenti',
                    child: Text('Valore'),
                  ),
                  columns: 4,
                  height: 200,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifica layout'));
      await tester.pumpAndSettle();
      for (final id in ['a', 'b']) {
        await tester.drag(
          find.byKey(ValueKey('resize-$id')),
          const Offset(17, 73),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(ValueKey('white-$id'))),
          rect(tester, id).size,
        );
      }
      await tester.drag(
        find.byKey(const ValueKey('drag-a')),
        const Offset(41, 17),
      );
      await tester.pumpAndSettle();
      final a = rect(tester, 'a'), b = rect(tester, 'b');
      expect(jsonDecode(store.data.values.single)['rects']['a'], [
        a.left,
        a.top,
        a.width,
        a.height,
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(rect(tester, 'a'), a);
      expect(rect(tester, 'b'), b);
      expect(tester.getSize(find.byKey(const ValueKey('white-b'))), b.size);
      expect(tester.takeException(), isNull);
    },
  );
}
