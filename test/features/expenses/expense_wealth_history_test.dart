import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_workbook.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_wealth_history.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_year_table.dart';
import 'package:monitoraggio_personale_desktop/features/markets/presentation/finance_widgets.dart';
import 'package:monitoraggio_personale_desktop/features/investments/portfolio.dart';
import 'package:monitoraggio_personale_desktop/features/investments/portfolio_history_card.dart';

class _Portfolio extends ChangeNotifier implements PortfolioController {
  List<PortfolioHistoryPoint> values = [
    PortfolioHistoryPoint(DateTime(2024, 1, 15), 5000, 4000.0),
    PortfolioHistoryPoint(DateTime(2025, 1, 1), 6000, 4000.0),
    PortfolioHistoryPoint(DateTime.now(), 7000, 4000.0),
  ];
  @override
  bool get loading => false;
  @override
  DateTime? get firstActivityDate => DateTime(2024, 1, 15);
  @override
  List<PortfolioHistoryPoint> historyFor(DateTime start, DateTime end) => values
      .where((p) => !p.date.isBefore(start) && !p.date.isAfter(end))
      .toList();
  void update() {
    values = [
      ...values.take(2),
      PortfolioHistoryPoint(DateTime.now(), 7100, 4000.0),
    ];
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ExpenseData _data() => ExpenseData(
  accounts: const {},
  liquids: null,
  pensionFund: null,
  funds: const {},
  sharedFactor: .5,
  tables: [
    for (final year in [2025, 2026])
      ExpenseYearTable(
        year,
        [
          ExpenseTableRow('Patrimonio', {
            for (var m = 1; m <= (year == 2025 ? 12 : 10); m++)
              m: year == 2025 ? 1000 + m * 50 : 1200 + m * 45,
          }, '2- Totale!W77'),
          ExpenseTableRow('Totale liquidi', {
            for (var m = 1; m <= (year == 2025 ? 12 : 10); m++)
              m: year == 2025 ? 500 + m * 20 : 650 - m * 10,
          }, '2- Totale!W78'),
          ExpenseTableRow('tot investito', {
            for (var m = 1; m <= (year == 2025 ? 12 : 10); m++)
              m: year == 2025 ? 300 + m * 5 : 400 + m * 6,
          }, '2- Totale!W79'),
        ],
        [for (var m = 1; m <= (year == 2025 ? 12 : 10); m++) m],
        '2- Totale!W76:$year',
        true,
      ),
  ],
  transactions: const [],
  availableMonths: const {},
  warnings: const [],
  loadedAt: DateTime(2026, 10, 15),
  sourceName: 'Test',
);

void main() {
  test(
    'wealth KPIs use the exact previous-year month and preserve genuine zero values',
    () {
      final source = [
        TimeValue(DateTime(2026, 10), 120),
        TimeValue(DateTime(2025, 10), 100),
        TimeValue(DateTime(2025, 1), 0),
      ];
      final series = ExpenseWealthSeries('Patrimonio', source);
      expect(series.latest!.value, 120);
      expect(series.minimum, 0);
      expect(series.maximum, 120);
      expect(series.annualChange, 20);
      expect(
        source.first.value,
        120,
      ); // Input data is never reordered in place.
      expect(
        ExpenseWealthSeries('Senza confronto', [
          TimeValue(DateTime(2025, 9), 100),
          TimeValue(DateTime(2026, 10), 120),
        ]).annualChange,
        isNull,
      );
      expect(
        ExpenseWealthSeries('Base zero', [
          TimeValue(DateTime(2025, 10), 0),
          TimeValue(DateTime(2026, 10), 120),
        ]).annualChange,
        isNull,
      );
      final empty = ExpenseWealthSeries('Vuoto', const []);
      expect(empty.latest, isNull);
      expect(empty.minimum, isNull);
      expect(empty.maximum, isNull);
      expect(empty.annualChange, isNull);
    },
  );

  testWidgets(
    'Excel wealth and liquidity with the shared portfolio card stay responsive',
    (tester) async {
      tester.view.physicalSize = const Size(1640, 1020);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (Platform.environment['EXPENSES_CAPTURE'] == '1') {
        for (final e in {
          'Segoe UI Variable': 'C:/Windows/Fonts/segoeui.ttf',
          'MaterialIcons':
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final font = File(e.value);
          if (font.existsSync())
            await (FontLoader(e.key)..addFont(
                  Future.value(ByteData.sublistView(font.readAsBytesSync())),
                ))
                .load();
        }
      }
      final image = GlobalKey();
      final portfolio = _Portfolio();
      addTearDown(portfolio.dispose);
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
                  child: ExpenseWealthHistory(
                    data: _data(),
                    year: 2026,
                    portfolio: portfolio,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseWealthChart), findsNWidgets(2));
      expect(find.byType(PortfolioHistoryCard), findsOneWidget);
      expect(find.byType(FinanceChart), findsOneWidget);
      expect(find.text('Valore attuale'), findsNWidgets(2));
      expect(find.text('Variazione (1 anno)'), findsNWidgets(2));
      expect(find.text('Massimo'), findsNWidgets(2));
      expect(find.text('Minimo'), findsNWidgets(2));
      expect(find.text('+10,0%'), findsOneWidget);
      expect(find.text('-21,4%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, image);
      final chart = tester.getRect(find.byType(ExpenseWealthChart).first);
      await tester.tapAt(Offset(chart.left + 2, chart.top + 40));
      await tester.pumpAndSettle();
      expect(find.text('01/01/2025'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ExpenseWealthChart).first,
          matching: find.text('1.050,00 EUR'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Dati storici di dettaglio - 2026'));
      await tester.tap(find.text('Dati storici di dettaglio - 2026'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseYearTableView), findsOneWidget);
      for (final width in [1024.0, 390.0, 320.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Width $width');
      }
    },
  );

  testWidgets(
    'both sections show identical market history, ranges and live portfolio updates instead of Excel balances',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final portfolio = _Portfolio();
      addTearDown(portfolio.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  PortfolioHistoryCard(controller: portfolio),
                  ExpenseWealthHistory(
                    data: _data(),
                    year: 2026,
                    portfolio: portfolio,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioHistoryCard), findsNWidgets(2));
      void expectMatching(List<double> values) {
        final charts = tester
            .widgetList<FinanceChart>(find.byType(FinanceChart))
            .toList();
        expect(charts.length, 2);
        for (final chart in charts) {
          expect(chart.points.map((p) => p.value), values);
          expect(
            chart.second.map((p) => p.value),
            List.filled(values.length, 4000.0),
          );
          expect(chart.connectGaps, isFalse);
        }
        expect(
          charts[0].points.map((p) => p.time),
          charts[1].points.map((p) => p.time),
        );
      }

      expectMatching([5000, 6000, 7000]);
      for (final selector
          in tester
              .widgetList<RangeSelector>(find.byType(RangeSelector))
              .toList()) {
        selector.onChanged(FinanceRange.month);
      }
      await tester.pumpAndSettle();
      expectMatching([7000]);
      portfolio.update();
      await tester.pumpAndSettle();
      expectMatching([7100]);
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
      '${Directory.systemTemp.path}/spese-wealth-history.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
