import 'dart:async';
import 'dart:convert';
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

String text(String cell, String value) =>
    '<c r="$cell" t="inlineStr"><is><t>$value</t></is></c>';
String number(String cell, num value, {String? formula, int style = 0}) =>
    '<c r="$cell" s="$style">${formula == null ? '' : '<f>$formula</f>'}<v>$value</v></c>';
String row(int r, List<String> cells) => '<row r="$r">${cells.join()}</row>';
num serial(DateTime d) => DateTime.utc(
  d.year,
  d.month,
  d.day,
).difference(DateTime.utc(1899, 12, 30)).inDays;
Uint8List fixture({bool factor = true}) {
  final total =
      '<worksheet><sheetData>${[
        row(2, [text('W2', 'Conto principale'), number('X2', 100, formula: 'SUM(A1:A2)'), text('AC2', 'Fondo Spese'), number('AD2', 5), if (factor) number('AF2', 0.4)]),
        row(3, [text('W3', 'Sottoconto'), number('X3', 20), text('Z3', 'Fondo pensione'), number('AA3', 200), text('AC3', 'Fondo Risparmi'), number('AD3', 30)]),
        row(5, [text('W5', 'Portafoglio digitale'), number('X5', 0)]),
        row(8, [text('W8', 'Totale liquidi'), number('X8', 150)]),
        row(38, [number('A38', 2024), number('P38', 2027)]),
        row(39, [text('A39', 'Categoria'), text('B39', 'Gennaio'), text('C39', 'Febbraio'), text('P39', 'Categoria'), text('Q39', 'Gennaio'), text('R39', 'Febbraio')]),
        row(40, [text('A40', 'Casa'), number('B40', 100), number('C40', 110), text('P40', 'Casa'), number('Q40', 120), number('R40', 130)]),
        row(41, [text('A41', 'Totale spese'), number('B41', 100), number('C41', 110), text('P41', 'Nuova categoria'), number('Q41', 20), number('R41', 25)]),
        row(42, [text('P42', 'Totale spese'), number('Q42', 140), number('R42', 155)]),
        row(76, [number('A76', 2024)]),
        row(77, [text('A77', 'Voce'), text('B77', 'Gennaio'), text('C77', 'Febbraio')]),
        row(78, [text('A78', 'Patrimonio'), number('B78', 1000), number('C78', 1100)]),
        row(79, [text('A79', 'Totale liquidi'), number('B79', 100), number('C79', 200)]),
        row(80, [text('A80', 'Investito'), number('B80', 300), number('C80', 400)]),
      ].join()}</sheetData><mergeCells><mergeCell ref="A38:N38"/><mergeCell ref="P38:AC38"/><mergeCell ref="A76:N76"/></mergeCells></worksheet>';
  final ledger =
      '<worksheet><sheetData>${[
        row(1, [number('DN1', 2026), number('DR1', 2026)]),
        row(2, [text('DN2', 'Settembre'), text('DR2', 'Ottobre')]),
        row(3, [text('DN3', 'Data'), text('DP3', 'Spese'), text('DR3', 'Data'), text('DT3', 'Spese'), text('DU3', 'Conto')]),
        row(4, [number('DN4', serial(DateTime(2026, 9, 30)), style: 1), number('DP4', 90), number('DR4', serial(DateTime(2026, 10, 1)), style: 1), text('DS4', 'Condivisa'), number('DT4', 100), text('DU4', 'C')]),
        row(5, [number('DR5', serial(DateTime(2026, 10, 2)), style: 1), text('DS5', 'Personale'), number('DT5', 30)]),
      ].join()}</sheetData><mergeCells><mergeCell ref="DN1:DQ1"/><mergeCell ref="DN2:DQ2"/><mergeCell ref="DR1:DU1"/><mergeCell ref="DR2:DU2"/></mergeCells></worksheet>';
  final archive = Archive();
  final files = {
    'xl/workbook.xml':
        '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="1- Spese" sheetId="1" r:id="r1"/><sheet name="2- Totale" sheetId="2" r:id="r2"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="worksheets/sheet2.xml"/></Relationships>',
    'xl/styles.xml':
        '<styleSheet><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>',
    'xl/worksheets/sheet1.xml': ledger,
    'xl/worksheets/sheet2.xml': total,
  };
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

class _Repository implements ExpenseRepository {
  int downloads = 0;
  @override
  Future<Uri> beginMicrosoftConnect() async => Uri.parse(
    'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
  );
  ExpenseSettings settings = const ExpenseSettings();
  final events = StreamController<ExpenseSettings>.broadcast(sync: true);
  @override
  Future<ExpenseSettings> loadSettings() async => settings;
  @override
  Stream<ExpenseSettings> watchSettings() => events.stream;
  @override
  Future<Uint8List> fetchWorkbook(String link) async {
    downloads++;
    return fixture();
  }

  @override
  Future<ExpenseSettings> saveSettings({
    String? sourceUrl,
    String? month,
    double? limit,
    List<String>? chartMetrics,
  }) async {
    settings = ExpenseSettings(
      sourceUrl: sourceUrl ?? settings.sourceUrl,
      budgets: {...settings.budgets, if (month != null) month: limit!},
      chartMetrics: chartMetrics ?? settings.chartMetrics,
    );
    events.add(settings);
    return settings;
  }
}

class _Portfolio extends ChangeNotifier implements PortfolioController {
  @override
  bool get loading => false;
  @override
  bool get complete => true;
  @override
  double get totalValue => 700;
  @override
  DateTime? get firstActivityDate => null;
  @override
  List<PortfolioHistoryPoint> historyFor(DateTime start, DateTime end) => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'recognizes variable year tables, cached formulas and source liquidity',
    () {
      final data = readExpenseData(ExpenseWorkbook.decode(fixture()));
      expect(data.liquids, 150); // Do not sum or duplicate sub-accounts.
      expect(data.accounts['Conto principale'], 100);
      expect(data.accounts['Portafoglio digitale'], 0);
      expect(data.pensionFund, 200);
      expect(data.tables.where((t) => !t.wealth).map((t) => t.year), [
        2024,
        2027,
      ]);
      expect(
        data.tables.firstWhere((t) => t.year == 2024 && !t.wealth).rows.length,
        2,
      );
      expect(data.tables.firstWhere((t) => t.year == 2027).rows.length, 3);
      expect(data.history('Patrimonio').map((p) => p.$2), [1000, 1100]);
    },
  );
  test(
    'finds October from dynamic headers and applies AF2 only to C expenses',
    () {
      final data = readExpenseData(ExpenseWorkbook.decode(fixture()));
      final month = data.month(DateTime(2026, 10));
      expect(month.map((t) => t.amount), [40, 30]);
      expect(month.fold<double>(0, (sum, t) => sum + t.amount!), 70);
      expect(data.month(DateTime(2026, 9)).single.amount, 90);
      expect(month.first.reference, '1- Spese!DT4');
    },
  );
  test('missing shared factor never becomes fake zero spend', () {
    final data = readExpenseData(
      ExpenseWorkbook.decode(fixture(factor: false)),
    );
    expect(data.month(DateTime(2026, 10)).first.amount, isNull);
    expect(data.warnings.any((w) => w.contains('AF2')), isTrue);
    expect(
      () => ExpenseWorkbook.decode(
        Uint8List.fromList(utf8.encode('<html>Login</html>')),
      ),
      throwsFormatException,
    );
  });
  test(
    'monthly caps survive controller recreation and sync without overwriting other months',
    () async {
      final repo = _Repository(),
          first = ExpenseController(repository: _Repository());
      first.dispose();
      final pc = ExpenseController(repository: repo),
          phone = ExpenseController(repository: repo);
      addTearDown(() {
        pc.dispose();
        phone.dispose();
      });
      await pc.load();
      await phone.load();
      await pc.save(month: '2026-10', limit: 1800);
      expect(phone.settings.limitFor('2026-10'), 1800);
      await phone.save(month: '2026-11', limit: 1700);
      expect(pc.settings.limitFor('2026-10'), 1800);
      expect(pc.settings.limitFor('2026-11'), 1700);
      final next = ExpenseController(repository: repo);
      addTearDown(next.dispose);
      await next.load();
      expect(next.settings.limitFor('2026-10'), 1800);
    },
  );
  testWidgets(
    'refreshes the live source only while active and skips decoding unchanged bytes',
    (tester) async {
      final repo = _Repository()
        ..settings = const ExpenseSettings(
          sourceUrl: 'https://1drv.ms/x/example',
        );
      final controller = ExpenseController(repository: repo);
      await controller.load();
      final original = controller.data;
      controller.setActive(true);
      await tester.pump(ExpenseController.syncInterval);
      await tester.pump();
      expect(repo.downloads, 2);
      expect(identical(controller.data, original), isTrue);
      controller.setActive(false);
      await tester.pump(const Duration(minutes: 2));
      expect(repo.downloads, 2);
      controller.dispose();
    },
  );
  testWidgets(
    'Spese shows Excel liquidity and app investments and opens the link section',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(1354, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ExpenseController(repository: _Repository());
      controller.data = readExpenseData(ExpenseWorkbook.decode(fixture()));
      final portfolio = _Portfolio();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: ExpensesPage(controller: controller, portfolio: portfolio),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Spese'), findsOneWidget);
      expect(find.text('Grafico personalizzato'), findsNothing);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        expenseMonthKey(DateTime.now()),
      );
      expect(find.text('1.050,00 EUR'), findsOneWidget);
      expect(find.text('700,00 EUR'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Fonte Excel'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Fonte Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Link OneDrive'), findsOneWidget);
      expect(find.text('Salva link sul server'), findsOneWidget);
      expect(find.text('Collega OneDrive'), findsOneWidget);
      expect(find.text('Leggi una copia .xlsx'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      portfolio.dispose();
    },
  );
}
