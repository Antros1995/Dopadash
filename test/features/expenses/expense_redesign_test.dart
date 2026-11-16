import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/application/expense_controller.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/data/expense_repository.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_summary.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_workbook.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_dashboard_widgets.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_spending_chart.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_transactions.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expenses_page.dart';
import 'package:monitoraggio_personale_desktop/features/investments/portfolio.dart';
import 'expenses_test.dart' as xml;

class _Repo implements ExpenseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No network');
}

class _Portfolio extends ChangeNotifier implements PortfolioController {
  @override
  bool get loading => false;
  @override
  bool get complete => true;
  @override
  double get totalValue => 700;
  @override
  List<PortfolioHistoryPoint> historyFor(DateTime start, DateTime end) => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ExpenseData _data(List<ExpenseTransaction> records, {DateTime? read}) =>
    ExpenseData(
      accounts: const {},
      liquids: 150,
      pensionFund: 200,
      funds: const {},
      sharedFactor: .5,
      tables: const [],
      transactions: records,
      availableMonths: {'2026-09', '2026-10', '2026-11'},
      warnings: const [],
      loadedAt: read ?? DateTime(2026, 10, 15),
      sourceName: 'Test',
    );

void main() {
  test(
    'monthly metrics reconcile, compare equal windows and never extend the actual curve',
    () {
      final data = _data([
        ExpenseTransaction(DateTime(2026, 9, 2), 'Casa', 100, 100, false, 'A1'),
        ExpenseTransaction(
          DateTime(2026, 9, 28),
          'Casa',
          900,
          900,
          false,
          'A2',
        ),
        ExpenseTransaction(DateTime(2026, 10, 2), 'Casa', 80, 40, true, 'B1'),
        ExpenseTransaction(
          DateTime(2026, 10, 10),
          'Spesa',
          30,
          30,
          false,
          'B2',
        ),
        ExpenseTransaction(
          DateTime(2026, 10, 28),
          'Spesa',
          900,
          900,
          false,
          'B3',
        ),
      ]);
      final summary = ExpenseMonthSummary(
        data,
        DateTime(2026, 10),
        now: DateTime(2026, 10, 15),
      );
      expect(summary.spent, 70);
      expect(summary.change, -30);
      expect(summary.average, closeTo(70 / 15, .0001));
      expect(summary.cumulative.last, (DateTime(2026, 10, 10), 70));
      expect(
        summary.categories.fold<double>(0, (sum, e) => sum + e.value!),
        70,
      );
      expect(
        ExpenseMonthSummary(
          data,
          DateTime(2026, 11),
          now: DateTime(2026, 10, 15),
        ).spent,
        isNull,
      );
      final missing = ExpenseMonthSummary(
        _data([
          ExpenseTransaction(
            DateTime(2026, 10, 2),
            'Casa',
            80,
            null,
            true,
            'B1',
          ),
        ]),
        DateTime(2026, 10),
        now: DateTime(2026, 10, 15),
      );
      expect(missing.spent, isNull);
      expect(missing.cumulative, isEmpty);
    },
  );

  testWidgets(
    'desktop composition, source access, transactions and responsive rendering',
    (tester) async {
      tester.view.physicalSize = const Size(1478, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fontPath = File('C:/Windows/Fonts/segoeui.ttf');
      if (fontPath.existsSync()) {
        final font = FontLoader('Segoe UI Variable')
          ..addFont(
            Future.value(ByteData.sublistView(fontPath.readAsBytesSync())),
          );
        await font.load();
        final icons = File(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (icons.existsSync())
          await (FontLoader('MaterialIcons')..addFont(
                Future.value(ByteData.sublistView(icons.readAsBytesSync())),
              ))
              .load();
      }
      final original = Platform.environment['EXPENSES_TEST_WORKBOOK'];
      final data = readExpenseData(
        ExpenseWorkbook.decode(
          original == null ? xml.fixture() : File(original).readAsBytesSync(),
        ),
      );
      final controller = ExpenseController(repository: _Repo())..data = data;
      final portfolio = _Portfolio();
      final page = GlobalKey<ExpensesPageState>(), image = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: RepaintBoundary(
              key: image,
              child: ColoredBox(
                color: AppColors.canvas,
                child: ExpensesPage(
                  key: page,
                  controller: controller,
                  portfolio: portfolio,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseStat), findsNWidgets(4));
      final stats = tester.getRect(find.byType(ExpenseStat).first);
      expect(tester.getRect(find.byType(ExpenseStat).last).top, stats.top);
      final chart = tester.getRect(find.byType(ExpenseSpendingChart));
      final control = tester.getRect(find.byType(ExpenseBudgetControl));
      expect(chart.left, lessThan(control.left));
      expect(chart.width / control.width, inInclusiveRange(1.8, 2.1));
      await _capture(tester, image, 'spese-desktop.png');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Vedi tutte ›'));
      await tester.pumpAndSettle();
      expect(find.text('Riduci ‹'), findsOneWidget);
      await tester.tap(find.text('Vedi tutti ›'));
      await tester.pumpAndSettle();
      for (final fund in data.funds.keys) expect(find.text(fund), findsWidgets);

      page.currentState!.showSection('Riepilogo annuale');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Filtra categorie della tabella'),
        'Casa',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      page.currentState!.showSection('Fonte Excel');
      await tester.pumpAndSettle();
      expect(find.text('Link OneDrive'), findsOneWidget);
      expect(find.text('Collega OneDrive'), findsOneWidget);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(ExpenseTransactions));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opzioni transazioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mostra storico completo'));
      await tester.pumpAndSettle();
      expect(find.text('Storico completo'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cerca transazioni…'),
        'nessunarisultanza',
      );
      await tester.pumpAndSettle();
      expect(find.text('Nessuna transazione corrispondente.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cerca transazioni…'),
        '',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Filtra'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Condiviso C').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);
      expect(tester.takeException(), isNull);
      page.currentState!.showSection('Panoramica');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mese successivo'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ExpenseStat>(find.byType(ExpenseStat).first).value,
        isNull,
      );
      await tester.tap(find.byTooltip('Mese precedente'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ExpenseStat>(find.byType(ExpenseStat).first).value,
        isNotNull,
      );

      tester.view.physicalSize = const Size(390, 844);
      page.currentState!.showSection('Panoramica');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, image, 'spese-mobile.png');
      for (final section in [
        'Budget mensile',
        'Conti e fondi',
        'Riepilogo annuale',
        'Patrimonio',
      ]) {
        page.currentState!.showSection(section);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: section);
      }
      for (final size in [const Size(1024, 900), const Size(320, 740)]) {
        tester.view.physicalSize = size;
        page.currentState!.showSection('Panoramica');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      portfolio.dispose();
    },
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['EXPENSES_CAPTURE'] != '1') return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      '${Directory.systemTemp.path}/$name',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
