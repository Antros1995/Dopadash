import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/application/expense_controller.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/data/expense_repository.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_workbook.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expenses_page.dart';
import 'package:monitoraggio_personale_desktop/features/investments/portfolio.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_wealth_history.dart';
import 'package:monitoraggio_personale_desktop/features/markets/presentation/finance_widgets.dart';
import 'expenses_test.dart' as xml;

Uint8List _template() {
  final months = [
    for (var m = 1; m <= 12; m++)
      xml.number(
        '${columnName(23 + m)}38',
        xml.serial(DateTime(2026, m)),
        style: 2,
      ),
  ].join();
  final total =
      '<worksheet><sheetData>${[
        xml.row(2, [xml.number('AF2', .5)]),
        xml.row(3, [xml.text('Z3', 'Fondo pensione'), xml.number('AA3', 200)]),
        xml.row(8, [xml.text('W8', 'Totale liquidi'), xml.number('X8', 100)]),
        xml.row(11, [xml.number('W11', 2026)]),
        '<row r="13">${months.replaceAll('38', '13')}</row>',
        '<row r="38">$months</row>',
        xml.row(39, [xml.text('W39', 'Casa'), xml.number('X39', 10), xml.number('AG39', 20)]),
        xml.row(40, [xml.text('W40', 'Nuova categoria'), xml.number('X40', 5), xml.number('AG40', 10)]),
        xml.row(41, [xml.text('W41', 'ToT spese'), xml.number('X41', 15), xml.number('AG41', 30)]),
        xml.row(42, [xml.text('W42', 'TOT netto investimenti'), xml.number('X42', 15), xml.number('AG42', 30)]),
        xml.row(43, [xml.text('W43', 'check'), xml.number('X43', 0)]),
        xml.row(76, [xml.text('W76', 'Andamento patrimonio'), xml.number('X76', xml.serial(DateTime(2026, 1)), style: 2), xml.number('Y76', xml.serial(DateTime(2026, 2)), style: 2)]),
        xml.row(77, [xml.text('W77', 'Patrimonio'), xml.number('X77', 1000), xml.number('AG77', 1500)]),
        xml.row(78, [xml.text('W78', 'Totale liquidi'), xml.number('X78', 300), xml.number('AG78', 500)]),
        xml.row(79, [xml.text('W79', 'tot investito'), xml.number('X79', 700), xml.number('AG79', 1000)]),
      ].join()}</sheetData><mergeCells><mergeCell ref="W11:AI11"/></mergeCells></worksheet>';
  final ledger =
      '<worksheet><sheetData>${[
        xml.row(1, [xml.text('DR1', 'Ottobbre')]),
        xml.row(3, [xml.number('DR3', xml.serial(DateTime(2026, 10)), style: 1), xml.number('DT3', 999)]),
        xml.row(37, [xml.number('CD37', 2026)]),
        xml.row(39, [xml.text('DR39', 'Ottobbre'), xml.text('DS39', 'Categoria'), xml.number('DT39', 30)]),
        xml.row(40, [xml.number('DR40', xml.serial(DateTime(2026, 10)), style: 1), xml.text('DS40', 'Casa'), xml.number('DT40', 40), xml.text('DU40', 'C')]),
        xml.row(41, [xml.number('DR41', xml.serial(DateTime(2026, 10, 2)), style: 1), xml.text('DS41', 'Spesa'), xml.number('DT41', 10)]),
      ].join()}</sheetData><mergeCells><mergeCell ref="DR1:DU1"/><mergeCell ref="CD37:ED37"/><mergeCell ref="DT39:DU39"/></mergeCells></worksheet>';
  final base = ZipDecoder().decodeBytes(xml.fixture());
  final archive = Archive();
  for (final file in base.files) {
    final bytes = file.name.endsWith('sheet1.xml')
        ? utf8.encode(ledger)
        : file.name.endsWith('sheet2.xml')
        ? utf8.encode(total)
        : file.name.endsWith('styles.xml')
        ? utf8.encode(
            '<styleSheet><cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="17"/></cellXfs></styleSheet>',
          )
        : file.content as List<int>;
    archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

class _NoNetworkRepository implements ExpenseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No network in this rendering check');
}

class _UnknownPortfolio extends ChangeNotifier implements PortfolioController {
  @override
  bool get loading => false;
  @override
  bool get complete => false;
  @override
  double get totalValue => 0;
  @override
  List<PortfolioHistoryPoint> historyFor(DateTime start, DateTime end) => [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Portfolio is intentionally unavailable');
}

void main() {
  test(
    'reads distant year bands, repeated month columns and Ottobbre without bank totals',
    () {
      final data = readExpenseData(
        ExpenseWorkbook.decode(_template()),
        now: DateTime(2026, 10, 14),
      );
      expect(data.tables.where((t) => !t.wealth).single.rows.length, 4);
      expect(data.tables.where((t) => t.wealth).single.rows.length, 3);
      expect(data.month(DateTime(2026, 10)).map((t) => t.amount), [20, 10]);
      expect(data.history('Patrimonio').last, (DateTime(2026, 10), 1500));
      expect(data.history('Totale liquidi').last.$2, 500);
      expect(data.history('tot investito').last.$2, 1000);
      expect(expenseMonth('Novembe'), 11);
    },
  );

  final workbookPath = Platform.environment['EXPENSES_TEST_WORKBOOK'];
  testWidgets(
    'original workbook renders October, annual rows and all three real histories',
    (tester) async {
      final book = ExpenseWorkbook.decode(
        File(workbookPath!).readAsBytesSync(),
      );
      final data = readExpenseData(book);
      final october = data.month(DateTime(2026, 10));
      expect(october, isNotEmpty);
      final expected = book
          .sheet('1spese')!
          .at(39, cellCoordinate('DT39').$2)!
          .number!;
      expect(
        october.fold<double>(0, (s, t) => s + t.amount!),
        closeTo(expected, .01),
      );
      expect(data.tables.where((t) => !t.wealth).map((t) => t.year), [
        2024,
        2025,
        2026,
      ]);
      expect(
        data.tables.where((t) => !t.wealth).every((t) => t.rows.length == 26),
        isTrue,
      );
      expect(book.formulaErrors.single, contains('B124 (#VALUE!)'));
      expect(book.missingFormulaResults, 0);
      for (final label in ['Patrimonio', 'Totale liquidi', 'tot investito']) {
        expect(data.history(label), isNotEmpty);
        expect(data.history(label).first.$1, DateTime(2024, 5));
        expect(data.history(label).last.$1, DateTime(2026, 10));
      }
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ExpenseController(repository: _NoNetworkRepository())
        ..data = data;
      final portfolio = _UnknownPortfolio();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: ExpensesPage(controller: controller, portfolio: portfolio),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        '2026-10',
      );
      expect(find.text('Riepilogo annuale non disponibile.'), findsNothing);
      expect(
        find.text('Serie storica non disponibile per questo intervallo.'),
        findsOneWidget,
      );
      expect(find.text('2026 · 26 voci · Importi in EUR'), findsOneWidget);
      expect(find.byType(ExpenseWealthChart), findsNWidgets(2));
      expect(
        tester.widget<FinanceChart>(find.byType(FinanceChart)).points,
        isEmpty,
      );
      expect(
        tester
            .widgetList<ExpenseWealthChart>(find.byType(ExpenseWealthChart))
            .every((c) => c.series.points.isNotEmpty),
        isTrue,
      );
      expect(find.text('Grafico personalizzato'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      portfolio.dispose();
    },
    skip: workbookPath == null,
  );
}
