import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_workbook.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_summary.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_dashboard_widgets.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_transactions.dart';
import 'expenses_test.dart' as xml;

Uint8List _fixture() {
  final archive = Archive();
  for (final file in ZipDecoder().decodeBytes(xml.fixture()).files) {
    final bytes = file.name.endsWith('sheet1.xml')
        ? utf8.encode(
            utf8
                .decode(file.content as List<int>)
                .replaceFirst(
                  '</sheetData>',
                  '${xml.row(6, [xml.text('DS6', 'Spesa'), xml.number('DT6', 50), xml.text('DU6', 'R')])}${xml.row(7, [xml.text('DS7', 'Spesa'), xml.number('DT7', 20), xml.text('DU7', 'C')])}</sheetData>',
                ),
          )
        : file.content as List<int>;
    archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  test(
    'undated source rows count in their actual month, apply C once, and never enter a fabricated daily point',
    () {
      final data = readExpenseData(
        ExpenseWorkbook.decode(_fixture()),
        now: DateTime(2026, 10, 16),
      );
      final summary = ExpenseMonthSummary(
        data,
        DateTime(2026, 10),
        now: DateTime(2026, 10, 16),
      );
      expect(summary.records.length, 4);
      expect(summary.undated.map((t) => t.reference).toSet(), {
        '1- Spese!DT6',
        '1- Spese!DT7',
      });
      expect(summary.undated.map((t) => t.amount), [50, 8]);
      expect(summary.spent, 128);
      expect(summary.undatedTotal, 58);
      expect(summary.cumulative.last, (DateTime(2026, 10, 2), 70));
      expect(
        summary.change,
        isNull,
      ); // No misleading comparison on unknown days.
    },
  );
  testWidgets(
    'budget residue includes undated expenses and transactions label and filter them honestly',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = readExpenseData(
        ExpenseWorkbook.decode(_fixture()),
        now: DateTime(2026, 10, 16),
      );
      final summary = ExpenseMonthSummary(
        data,
        DateTime(2026, 10),
        now: DateTime(2026, 10, 16),
      );
      final transactions = GlobalKey<ExpenseTransactionsState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    height: 280,
                    child: ExpenseBudgetControl(
                      summary: summary,
                      limit: 1900,
                      onEdit: () {},
                    ),
                  ),
                  ExpenseTransactions(
                    key: transactions,
                    transactions: data.transactions,
                    month: DateTime(2026, 10),
                    factor: data.sharedFactor,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1.772,00 EUR'), findsOneWidget);
      expect(find.text('Senza data'), findsNWidgets(2));
      transactions.currentState!.showUndated();
      await tester.pumpAndSettle();
      expect(find.text('01/10/2026'), findsNothing);
      expect(find.text('02/10/2026'), findsNothing);
      expect(find.text('−50,00 EUR'), findsOneWidget);
      expect(find.text('−8,00 EUR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  final original = Platform.environment['EXPENSES_TEST_WORKBOOK'];
  test(
    'original OneDrive workbook reconciles Excel monthly total, categories, daily series and undated amounts',
    () {
      final book = ExpenseWorkbook.decode(File(original!).readAsBytesSync());
      final data = readExpenseData(book, now: DateTime(2026, 10, 16));
      final summary = ExpenseMonthSummary(
        data,
        DateTime(2026, 10),
        now: DateTime(2026, 10, 16),
      );
      final expected = book
          .sheet('1spese')!
          .at(39, cellCoordinate('DT39').$2)!
          .number!;
      expect(summary.spent, closeTo(expected, .001));
      expect(summary.undated, isNotEmpty);
      expect(
        summary.cumulative.last.$2 + summary.undatedTotal!,
        closeTo(expected, .001),
      );
      expect(
        summary.categories.fold<double>(0, (sum, e) => sum + e.value!),
        closeTo(expected, .001),
      );
    },
    skip: original == null,
  );
}
