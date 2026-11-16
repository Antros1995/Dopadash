import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_workbook.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_year_table.dart';
import 'expenses_test.dart' as source;

Uint8List _noisyWorkbook({bool currentHistory = false}) {
  final original = ZipDecoder().decodeBytes(source.fixture());
  final result = Archive();
  for (final file in original.files) {
    var bytes = file.content as List<int>;
    if (file.name.endsWith('sheet2.xml')) {
      var xml = utf8
          .decode(bytes)
          .replaceFirst(
            source.number('X8', 150),
            source.number('X8', 150, style: 3),
          );
      xml = xml.replaceFirst(
        '</sheetData>',
        '${[
          source.row(40, [source.number('AZ40', 2010), source.number('BC40', 2185)]),
          source.row(41, [source.text('BA41', 'Gennaio'), source.text('BB41', 'Febbraio'), source.text('BD41', 'Gennaio'), source.text('BE41', 'Febbraio')]),
          source.row(42, [source.text('AZ42', 'Patrimonio'), source.number('BA42', 2010), source.text('BC42', 'Patrimonio'), source.number('BD42', 0)]),
          if (currentHistory) ...[
            source.row(100, [source.number('A100', 2026)]),
            source.row(101, [source.text('A101', 'Voce'), source.text('B101', 'Settembre'), source.text('C101', 'Ottobre'), source.text('D101', 'Novembre')]),
            source.row(102, [source.text('A102', 'Patrimonio'), source.number('B102', 46000), source.number('C102', 50000), source.number('D102', 0)]),
          ],
        ].join()}</sheetData>',
      );
      if (currentHistory)
        xml = xml.replaceFirst(
          '</mergeCells>',
          '<mergeCell ref="A100:N100"/></mergeCells>',
        );
      bytes = utf8.encode(xml);
    } else if (file.name.endsWith('sheet1.xml')) {
      var xml = utf8
          .decode(bytes)
          .replaceFirst(
            source.text('DR2', 'Ottobre'),
            source.number(
              'DR2',
              source.serial(DateTime(2026, 10, 20)),
              style: 2,
            ),
          );
      xml = xml
          .replaceFirst(
            '</sheetData>',
            '${[
              source.row(2, [source.number('EA2', source.serial(DateTime(1935, 2)), style: 1)]),
              source.row(3, [source.text('EA3', 'Data'), source.text('EC3', 'Spese')]),
              source.row(4, [source.number('EA4', source.serial(DateTime(1935, 2, 2)), style: 1), source.number('EC4', 50)]),
            ].join()}</sheetData>',
          )
          .replaceFirst(
            '</mergeCells>',
            '<mergeCell ref="EA2:ED2"/></mergeCells>',
          );
      bytes = utf8.encode(xml);
    } else if (file.name.endsWith('styles.xml')) {
      bytes = utf8.encode(
        r'<styleSheet><numFmts count="2"><numFmt numFmtId="164" formatCode="mmmm"/><numFmt numFmtId="165" formatCode="0.00 \U\S\D"/></numFmts><cellXfs count="4"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/><xf numFmtId="165"/></cellXfs></styleSheet>',
      );
    }
    result.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(result)!);
}

void main() {
  test(
    'recognizes real year headings without interpreting amounts as 2010 or 2185',
    () {
      final data = readExpenseData(
        ExpenseWorkbook.decode(_noisyWorkbook()),
        now: DateTime(2026, 10, 14),
      );
      expect(data.liquids, 150); // The escaped USD label is not a date format.
      expect(data.tables.map((t) => t.year).toSet(), {2024, 2027});
      expect(data.history('Patrimonio').map((p) => p.$1.year).toSet(), {2024});
    },
  );
  test(
    'reads month-only Excel dates and excludes date-shaped 1935 headers',
    () {
      final data = readExpenseData(ExpenseWorkbook.decode(_noisyWorkbook()));
      expect(data.availableMonths, {'2026-09', '2026-10'});
      expect(data.month(DateTime(2026, 10)).map((t) => t.amount), [40, 30]);
      expect(expenseDate(DateTime(1935, 2)), isNull);
    },
  );
  test(
    'history preserves source values and ends at the current recorded month',
    () {
      final data = readExpenseData(
        ExpenseWorkbook.decode(_noisyWorkbook(currentHistory: true)),
        now: DateTime(2026, 10, 14),
      );
      expect(data.history('Patrimonio').last, (DateTime(2026, 10), 50000));
      expect(data.history('Patrimonio').first.$1, DateTime(2024, 1));
    },
  );
  testWidgets(
    'annual table scrolls months with fixed categories and no overflow',
    (tester) async {
      final table = ExpenseYearTable(
        2026,
        [
          ExpenseTableRow(
            'Spese casa e manutenzione con categoria molto lunga',
            {for (var m = 1; m <= 12; m++) m: 12345.67},
            '2- Totale!A40',
          ),
          ExpenseTableRow('Totale spese', {
            for (var m = 1; m <= 12; m++) m: 12345.67,
          }, '2- Totale!A41'),
        ],
        List.generate(12, (i) => i + 1),
        '2- Totale!A38',
        false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: ExpenseYearTableView(table: table),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final category = find.text(
        'Spese casa e manutenzione con categoria molto lunga',
      );
      final before = tester.getTopLeft(category);
      expect(find.byType(Scrollbar), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        greaterThan(0),
      );
      expect(tester.getTopLeft(category), before);
      expect(tester.takeException(), isNull);
    },
  );
}
