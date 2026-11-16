import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_workbook.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_annual_report.dart';

ExpenseYearTable _table() => ExpenseYearTable(
  2026,
  [
    ExpenseTableRow('Zeta', {
      for (var m = 1; m <= 12; m++)
        m: m == 1
            ? 10
            : m == 2
            ? 20
            : 0,
    }, '2- Totale!W39'),
    ExpenseTableRow('Amazon', {
      for (var m = 1; m <= 12; m++)
        m: m == 1
            ? 100
            : m == 2
            ? 50
            : 0,
    }, '2- Totale!W40'),
    ExpenseTableRow('Casa', {
      for (var m = 1; m <= 12; m++)
        m: m == 1
            ? 70
            : m == 2
            ? null
            : 0,
    }, '2- Totale!W41'),
    ExpenseTableRow('ToT spese', {
      for (var m = 1; m <= 12; m++)
        m: m == 1
            ? 110
            : m == 2
            ? 70
            : 0,
    }, '2- Totale!W42'),
  ],
  List.generate(12, (i) => i + 1),
  '2- Totale!W38',
  false,
);

void main() {
  testWidgets(
    'groups refunds and totals, keeps source amounts and marks education with a graduation cap',
    (tester) async {
      tester.view.physicalSize = const Size(1640, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = _table();
      Map<int, double?> values(double value) => {
        for (var m = 1; m <= 12; m++) m: m == 1 ? value : 0,
      };
      final table = ExpenseYearTable(
        2026,
        [
          ...base.rows,
          ExpenseTableRow('Istruzione', values(10), 'W50'),
          ExpenseTableRow('Rimborsi', values(-12), 'W51'),
          ExpenseTableRow('Rimborsi scalati', values(-7), 'W52'),
          ExpenseTableRow('TOT netto investimenti', values(120), 'W53'),
        ],
        base.months,
        base.reference,
        false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExpenseAnnualTable(table: table),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('🎓'), findsOneWidget);
      expect(find.text('ToT spese'), findsNothing);
      expect(find.text('Totale mensile'), findsOneWidget);
      expect(find.text('Totale netto investimenti'), findsOneWidget);
      expect(
        find.text('Rimborsi'),
        findsNWidgets(2),
      ); // Group heading + source row.
      expect(
        tester.getTopLeft(find.text('Rimborsi scalati')).dy,
        greaterThan(tester.getTopLeft(find.text('Istruzione')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Totale netto investimenti')).dy -
            tester.getTopLeft(find.text('Totale mensile')).dy,
        56,
      );
      expect(find.text('180,00'), findsOneWidget);
      expect(
        find.text('120,00'),
        findsNWidgets(2),
      ); // January and yearly net total.
      expect(table.rows.length, 8); // Original source rows are untouched.
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'annual totals preserve missing values and sum only source month columns',
    () {
      final table = _table();
      expect(annualRowTotal(table, table.rows[0]), 30);
      expect(annualRowTotal(table, table.rows[1]), 150);
      expect(annualRowTotal(table, table.rows[2]), isNull);
      expect(annualRowTotal(table, table.rows[3]), 180);
    },
  );

  testWidgets(
    'annual-only controls, source footer, sorting and sticky categories',
    (tester) async {
      tester.view.physicalSize = const Size(1640, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final table = _table();
      final data = ExpenseData(
        accounts: const {},
        liquids: null,
        pensionFund: null,
        funds: const {},
        sharedFactor: .5,
        tables: [table],
        transactions: [
          ExpenseTransaction(DateTime(2026, 1, 3), 'Zeta', 10, 10, false, 'B3'),
          ExpenseTransaction(
            DateTime(2026, 2, 3),
            'Amazon',
            50,
            50,
            false,
            'C3',
          ),
        ],
        availableMonths: {'2026-01', '2026-02'},
        warnings: const [],
        loadedAt: DateTime(2026, 10, 15),
        sourceName: 'Test',
      );
      if (Platform.environment['EXPENSES_CAPTURE'] == '1') {
        for (final e in {
          'Segoe UI Variable': 'C:/Windows/Fonts/segoeui.ttf',
          'MaterialIcons':
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final file = File(e.value);
          if (file.existsSync())
            await (FontLoader(e.key)..addFont(
                  Future.value(ByteData.sublistView(file.readAsBytesSync())),
                ))
                .load();
        }
      }
      final image = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: RepaintBoundary(
              key: image,
              child: ColoredBox(
                color: AppColors.canvas,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ExpenseAnnualReport(
                    data: data,
                    year: 2026,
                    onYearChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Totale 2026'), findsOneWidget);
      expect(find.text('% sul totale'), findsOneWidget);
      expect(find.text('16,7%'), findsOneWidget);
      expect(find.text('83,3%'), findsOneWidget);
      expect(find.text('100,0%'), findsOneWidget);
      expect(find.text('Trend mensile'), findsOneWidget);
      expect(find.text('Totale mensile'), findsOneWidget);
      expect(find.text('Dic'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(
        find.text('180,00'),
        findsOneWidget,
      ); // The source total is shown once, in the summary.
      expect(find.text('ToT spese'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(tester, image);

      await tester.tap(find.text('Totale 2026'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Amazon')).dy,
        lessThan(tester.getTopLeft(find.text('Zeta')).dy),
      );
      await tester.tap(find.text('Totale 2026'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Zeta')).dy,
        lessThan(tester.getTopLeft(find.text('Amazon')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Casa')).dy,
        greaterThan(tester.getTopLeft(find.text('Amazon')).dy),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Filtra categorie della tabella'),
        'Casa',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ExpenseAnnualTable),
          matching: find.text('Casa'),
        ),
        findsOneWidget,
      );
      expect(find.text('Amazon'), findsNothing);
      expect(find.text('100,0%'), findsOneWidget);
      expect(
        find.text('180,00'),
        findsOneWidget,
      ); // General source footer unaffected by filtering.
      await tester.enterText(
        find.widgetWithText(TextField, 'Filtra categorie della tabella'),
        '',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      final tableFinder = find.byType(ExpenseAnnualTable);
      final categoryBefore = tester.getTopLeft(find.text('Casa'));
      final horizontal = find.descendant(
        of: tableFinder,
        matching: find.byType(SingleChildScrollView),
      );
      await tester.ensureVisible(horizontal);
      await tester.pumpAndSettle();
      final beforeDrag = tester.getTopLeft(find.text('Casa'));
      await tester.drag(horizontal, const Offset(-700, 0));
      await tester.pumpAndSettle();
      final scrolling = tester.state<ScrollableState>(
        find.descendant(of: horizontal, matching: find.byType(Scrollable)),
      );
      expect(scrolling.position.pixels, greaterThan(0));
      expect(tester.getTopLeft(find.text('Casa')).dx, beforeDrag.dx);
      expect(categoryBefore.dx, beforeDrag.dx);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key) async {
  if (Platform.environment['EXPENSES_CAPTURE'] != '1') return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      '${Directory.systemTemp.path}/spese-annual-table.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
