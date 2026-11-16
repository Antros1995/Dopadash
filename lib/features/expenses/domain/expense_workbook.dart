import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const expenseMonths = [
  'Gen',
  'Feb',
  'Mar',
  'Apr',
  'Mag',
  'Giu',
  'Lug',
  'Ago',
  'Set',
  'Ott',
  'Nov',
  'Dic',
];
String expenseMonthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';
String expenseLabel(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9àèéìòù]'), '');

class WorkbookCell {
  const WorkbookCell(
    this.row,
    this.column,
    this.value, {
    this.formula,
    this.monthFormatted = false,
  });
  final int row, column;
  final Object? value;
  final String? formula;
  final bool monthFormatted;
  String get text => value is String ? (value as String).trim() : '';
  double? get number =>
      value is num ? (value as num).toDouble() : expenseNumber(text);
  String get reference => '${columnName(column)}$row';
}

class WorkbookMerge {
  const WorkbookMerge(this.top, this.left, this.bottom, this.right);
  final int top, left, bottom, right;
  bool contains(int r, int c) =>
      r >= top && r <= bottom && c >= left && c <= right;
}

class ExpenseSheet {
  ExpenseSheet(this.name, this.cells, this.merges);
  final String name;
  final Map<int, Map<int, WorkbookCell>> cells;
  final List<WorkbookMerge> merges;
  int get maxRow => cells.keys.fold(0, math.max);
  Iterable<WorkbookCell> get values => cells.values.expand((r) => r.values);
  WorkbookMerge? mergeAt(int r, int c) {
    for (final m in merges) {
      if (m.contains(r, c)) return m;
    }
    return null;
  }

  WorkbookCell? at(int r, int c) {
    final cell = cells[r]?[c];
    if (cell?.value != null) return cell;
    final merge = mergeAt(r, c);
    return merge == null ? cell : cells[merge.top]?[merge.left];
  }
}

class ExpenseWorkbook {
  ExpenseWorkbook(
    this.sheets,
    this.missingFormulaResults, {
    this.formulaErrors = const [],
    this.missingFormulaCells = const [],
  });
  final List<ExpenseSheet> sheets;
  final int missingFormulaResults;
  final List<String> formulaErrors, missingFormulaCells;
  ExpenseSheet? sheet(String normalizedName) {
    for (final s in sheets) {
      if (expenseLabel(s.name) == normalizedName) return s;
    }
    return null;
  }

  factory ExpenseWorkbook.decode(Uint8List bytes) {
    if (bytes.length > 25 * 1024 * 1024 ||
        bytes.length < 4 ||
        bytes[0] != 80 ||
        bytes[1] != 75) {
      throw const FormatException('Serve un file Excel .xlsx scaricabile.');
    }
    final zip = ZipDecoder().decodeBytes(bytes);
    if (zip.files.fold<int>(0, (sum, f) => sum + f.size) > 120 * 1024 * 1024) {
      throw const FormatException('Excel troppo grande.');
    }
    final files = {
      for (final f in zip.files)
        if (f.isFile) f.name: f,
    };
    XmlDocument document(String path) {
      final f = files[path];
      if (f == null) throw FormatException('Struttura Excel incompleta: $path');
      return XmlDocument.parse(utf8.decode(f.content as List<int>));
    }

    final strings = files.containsKey('xl/sharedStrings.xml')
        ? document('xl/sharedStrings.xml')
              .findAllElements('si')
              .map((n) => n.findAllElements('t').map((t) => t.innerText).join())
              .toList()
        : <String>[];
    final styles = <int>[];
    final formats = <int, String>{};
    if (files.containsKey('xl/styles.xml')) {
      final xml = document('xl/styles.xml');
      for (final n in xml.findAllElements('numFmt')) {
        formats[int.parse(n.getAttribute('numFmtId')!)] =
            n.getAttribute('formatCode') ?? '';
      }
      final xfs = xml.findAllElements('cellXfs').firstOrNull;
      if (xfs != null) {
        for (final n in xfs.findElements('xf')) {
          styles.add(int.tryParse(n.getAttribute('numFmtId') ?? '') ?? 0);
        }
      }
    }
    final book = document('xl/workbook.xml');
    final date1904 =
        book
            .findAllElements('workbookPr')
            .firstOrNull
            ?.getAttribute('date1904') ==
        '1';
    final rels = {
      for (final n in document(
        'xl/_rels/workbook.xml.rels',
      ).findAllElements('Relationship'))
        n.getAttribute('Id')!: n.getAttribute('Target')!,
    };
    final sheets = <ExpenseSheet>[];
    final formulaErrors = <String>[], missingFormulaCells = <String>[];
    var missing = 0, count = 0;
    for (final sheet in book.findAllElements('sheet')) {
      final name = sheet.getAttribute('name') ?? '';
      // Only the two source sheets are needed; the workbook remains untouched.
      if (!['1spese', '2totale'].contains(expenseLabel(name))) continue;
      final relation = sheet.attributes
          .where((a) => a.name.local == 'id')
          .firstOrNull
          ?.value;
      final target = rels[relation];
      if (target == null) continue;
      final path = target.startsWith('/')
          ? target.substring(1)
          : Uri.parse('xl/workbook.xml').resolve(target).path;
      final xml = document(path);
      final cells = <int, Map<int, WorkbookCell>>{};
      for (final cell in xml.findAllElements('c')) {
        if (++count > 600000)
          throw const FormatException('Excel troppo grande.');
        final ref = cell.getAttribute('r');
        if (ref == null) continue;
        final rc = cellCoordinate(ref);
        final raw = cell.findElements('v').firstOrNull?.innerText;
        final formula = cell.findElements('f').firstOrNull?.innerText;
        final type = cell.getAttribute('t');
        Object? value;
        var monthFormatted = false;
        if (type == 's' && raw != null) {
          final index = int.tryParse(raw);
          if (index != null && index >= 0 && index < strings.length)
            value = strings[index];
        } else if (type == 'inlineStr') {
          value = cell.findAllElements('t').map((n) => n.innerText).join();
        } else if (type == 'str') {
          value = raw;
        } else if (type == 'd') {
          value = DateTime.tryParse(raw ?? '');
        } else if (type != 'e' && raw != null) {
          final number = double.tryParse(raw);
          if (number != null && number.isFinite) {
            final style = int.tryParse(cell.getAttribute('s') ?? '') ?? 0;
            final format = style < styles.length ? styles[style] : 0;
            final code = (formats[format] ?? '').replaceAll(
              RegExp(r'"[^"]*"|\[[^\]]*\]|\\.|_.|\*.'),
              '',
            );
            final isDate =
                (format >= 14 && format <= 22) ||
                RegExp(
                  r'[dmy]|g{2}|a{2,4}',
                  caseSensitive: false,
                ).hasMatch(code);
            value = isDate ? excelDate(number, date1904: date1904) : number;
            monthFormatted =
                isDate &&
                (format == 17 ||
                    (RegExp('m', caseSensitive: false).hasMatch(code) &&
                        !RegExp(
                          '[dghs]',
                          caseSensitive: false,
                        ).hasMatch(code)));
          }
        }
        if (formula != null && value == null) {
          if (type == 'e' && raw != null && raw.isNotEmpty) {
            formulaErrors.add('$name!$ref ($raw)');
          } else {
            missing++;
            missingFormulaCells.add('$name!$ref');
          }
        }
        if (value == null && formula == null) continue;
        (cells[rc.$1] ??= {})[rc.$2] = WorkbookCell(
          rc.$1,
          rc.$2,
          value,
          formula: formula,
          monthFormatted: monthFormatted,
        );
      }
      final merges = <WorkbookMerge>[];
      for (final n in xml.findAllElements('mergeCell')) {
        final refs = (n.getAttribute('ref') ?? '').split(':');
        if (refs.length != 2) continue;
        final a = cellCoordinate(refs[0]), b = cellCoordinate(refs[1]);
        merges.add(WorkbookMerge(a.$1, a.$2, b.$1, b.$2));
      }
      sheets.add(ExpenseSheet(name, cells, merges));
    }
    return ExpenseWorkbook(
      sheets,
      missing,
      formulaErrors: formulaErrors,
      missingFormulaCells: missingFormulaCells,
    );
  }
}

String columnName(int column) {
  var c = column, name = '';
  while (c > 0) {
    c--;
    name = String.fromCharCode(65 + c % 26) + name;
    c ~/= 26;
  }
  return name;
}

(int, int) cellCoordinate(String ref) {
  final m = RegExp(
    r'^\$?([A-Z]+)\$?(\d+)$',
    caseSensitive: false,
  ).firstMatch(ref);
  if (m == null) throw const FormatException('Cella Excel non valida');
  var column = 0;
  for (final code in m.group(1)!.toUpperCase().codeUnits) {
    column = column * 26 + code - 64;
  }
  return (int.parse(m.group(2)!), column);
}

DateTime excelDate(double value, {bool date1904 = false}) {
  // Excel serials are wall-clock dates, not elapsed local time across DST.
  final utc = (date1904 ? DateTime.utc(1904) : DateTime.utc(1899, 12, 30)).add(
    Duration(milliseconds: (value * 86400000).round()),
  );
  return DateTime(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
  );
}

double? expenseNumber(String value) {
  var s = value.trim().replaceAll(RegExp(r'[€\s\u00a0]'), '');
  if (s.isEmpty) return null;
  final percent = s.endsWith('%');
  s = s.replaceAll('%', '');
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  final number = double.tryParse(s);
  return number == null || !number.isFinite
      ? null
      : percent
      ? number / 100
      : number;
}

class ExpenseTransaction {
  const ExpenseTransaction(
    this.date,
    this.description,
    this.originalAmount,
    this.amount,
    this.shared,
    this.reference, {
    this.hasExactDate = true,
  });
  // For undated entries, date identifies only the source column's month.
  // Never display that month anchor as an actual transaction day.
  final bool hasExactDate;
  final DateTime date;
  final String description, reference;
  final double originalAmount;
  final double? amount;
  final bool shared;
}

class ExpenseTableRow {
  const ExpenseTableRow(this.label, this.values, this.reference);
  final String label, reference;
  final Map<int, double?> values;
}

class ExpenseYearTable {
  const ExpenseYearTable(
    this.year,
    this.rows,
    this.months,
    this.reference,
    this.wealth,
  );
  final int year;
  final List<ExpenseTableRow> rows;
  final List<int> months;
  final String reference;
  final bool wealth;
}

class ExpenseData {
  ExpenseData({
    required this.accounts,
    required this.liquids,
    required this.pensionFund,
    required this.funds,
    required this.sharedFactor,
    required this.tables,
    required this.transactions,
    required this.availableMonths,
    required this.warnings,
    required this.loadedAt,
    required this.sourceName,
  });
  final Map<String, double?> accounts, funds;
  final double? liquids, pensionFund, sharedFactor;
  final List<ExpenseYearTable> tables;
  final List<ExpenseTransaction> transactions;
  final Set<String> availableMonths;
  final List<String> warnings;
  final DateTime loadedAt;
  final String sourceName;
  List<ExpenseTransaction> month(DateTime date) => transactions
      .where((t) => t.date.year == date.year && t.date.month == date.month)
      .toList();
  List<(DateTime, double)> history(String label) {
    final points = <DateTime, double>{};
    final lastMonth = DateTime(loadedAt.year, loadedAt.month);
    for (final table in tables.where((t) => t.wealth)) {
      for (final row in table.rows.where(
        (r) => expenseLabel(r.label) == expenseLabel(label),
      )) {
        for (final e in row.values.entries) {
          final month = DateTime(table.year, e.key);
          if (e.value != null && !month.isAfter(lastMonth))
            points[month] = e.value!;
        }
      }
    }
    final keys = points.keys.toList()..sort();
    return [for (final key in keys) (key, points[key]!)];
  }

  List<String> get historyMetrics => {
    for (final t in tables.where((t) => t.wealth))
      for (final r in t.rows) r.label,
  }.toList();
}

int? expenseMonth(Object? value) {
  if (value is DateTime) return value.month;
  if (value is! String) return null;
  final names = [
    'gennaio|january|gen|jan',
    'febbraio|february|feb',
    'marzo|march|mar',
    'aprile|april|apr',
    'maggio|may|mag',
    'giugno|june|giu|jun',
    'luglio|july|lug|jul',
    'agosto|august|ago|aug',
    'settembre|september|set|sett|sep|sept',
    'ottobre|ottobbre|october|ott|oct',
    'novembre|novembe|november|nov',
    'dicembre|december|dic|dec',
  ];
  for (var i = 0; i < names.length; i++) {
    if (RegExp(
      '^(${names[i]})(?:[ .\\-/]+(?:20\\d{2}|\\d{2}))?\$',
      caseSensitive: false,
    ).hasMatch(value.trim()))
      return i + 1;
  }
  return null;
}

int? expenseYear(Object? value) {
  if (value is DateTime)
    return value.year >= 2000 && value.year <= 2199 ? value.year : null;
  if (value is num && value == value.round() && value >= 2000 && value <= 2200)
    return value.toInt();
  final match = RegExp(r'\b(20\d{2}|21\d{2})\b').firstMatch('$value');
  return match == null ? null : int.parse(match.group(1)!);
}

int? _tableHeaderYear(ExpenseSheet sheet, WorkbookCell cell) {
  final year = expenseYear(cell.value);
  if (year == null) return null;
  final merge = sheet.mergeAt(cell.row, cell.column);
  if (merge == null ||
      merge.top != cell.row ||
      merge.left != cell.column ||
      merge.right <= merge.left)
    return null;
  if (cell.value is String &&
      !RegExp(
        r'^(?:anno\s+)?(?:20|21)\d{2}$',
        caseSensitive: false,
      ).hasMatch(cell.text))
    return null;
  return year;
}

class _MonthColumns {
  const _MonthColumns(this.row, this.columns);
  final int row;
  final Map<int, int> columns;
}

List<ExpenseYearTable> _readExpenseTables(ExpenseSheet sheet) {
  final result = <ExpenseYearTable>[];
  final lastRow = sheet.maxRow;
  final bands = sheet.values
      .where((c) => _tableHeaderYear(sheet, c) != null)
      .toList();
  for (final band in bands) {
    final year = _tableHeaderYear(sheet, band)!;
    final span = sheet.mergeAt(band.row, band.column)!;
    final following = bands
        .where(
          (b) =>
              b.row > band.row &&
              sheet.mergeAt(b.row, b.column)!.left <= span.right &&
              sheet.mergeAt(b.row, b.column)!.right >= span.left,
        )
        .map((b) => b.row)
        .toList();
    final endRow = following.isEmpty ? lastRow : following.reduce(math.min) - 1;
    final headers = <_MonthColumns>[];
    for (var row = band.row + 1; row <= endRow; row++) {
      final label = expenseLabel(sheet.at(row, span.left)?.text ?? '');
      if (['data', 'date', 'ggfinemese'].contains(label)) continue;
      final months = <int, int>{};
      for (var col = span.left + 1; col <= span.right; col++) {
        final cell = sheet.cells[row]?[col];
        if (cell == null) continue;
        final value = cell.value;
        if (value is DateTime &&
            (expenseYear(value) == null ||
                (!cell.monthFormatted && row > band.row + 5 && value.day != 1)))
          continue;
        final month = expenseMonth(value);
        if (month != null) months.putIfAbsent(month, () => col);
      }
      if (months.length >= 2 || (months.isNotEmpty && row <= band.row + 5)) {
        headers.add(_MonthColumns(row, months));
      }
    }
    if (headers.isEmpty) continue;

    List<ExpenseTableRow> rowsFrom(int firstRow, _MonthColumns header) {
      final rows = <ExpenseTableRow>[];
      var blanks = 0;
      final firstColumn = header.columns.values.reduce(math.min);
      for (var row = firstRow; row <= endRow; row++) {
        if (headers.any((h) => h.row == row) ||
            bands.any((b) => b.row == row && b.column == band.column))
          break;
        String label = '';
        for (var col = firstColumn - 1; col >= span.left; col--) {
          final text = sheet.at(row, col)?.text ?? '';
          if (text.isNotEmpty) {
            label = text;
            break;
          }
        }
        final normalized = expenseLabel(label);
        if (normalized == 'check' || normalized.contains('andamentopatrimonio'))
          break;
        final values = {
          for (final e in header.columns.entries)
            e.key: sheet.at(row, e.value)?.number,
        };
        if (label.isEmpty && values.values.every((v) => v == null)) {
          if (++blanks >= 2 && rows.isNotEmpty) break;
          continue;
        }
        blanks = 0;
        if (label.isEmpty ||
            expenseMonth(label) != null ||
            expenseYear(label) != null)
          continue;
        rows.add(
          ExpenseTableRow(
            label,
            values,
            '${sheet.name}!${columnName(firstColumn - 1)}$row',
          ),
        );
      }
      return rows;
    }

    void addTable(_MonthColumns header, int firstRow, {bool history = false}) {
      final rows = rowsFrom(firstRow, header);
      if (rows.isEmpty) return;
      final wealth =
          history ||
          rows.any(
            (r) => [
              'patrimonio',
              'totalepatrimonio',
              'totaleliquidi',
              'liquidi',
              'totinvestimenti',
              'totinvestito',
              'investito',
            ].contains(expenseLabel(r.label)),
          );
      final heading = expenseLabel(sheet.at(header.row, span.left)?.text ?? '');
      // Bank statistics and withdrawal schedules also use monthly dates.
      // The requested expense table ends with its expense total/category heading.
      if (!wealth &&
          !rows.any(
            (r) => ['totspese', 'totalespese'].contains(expenseLabel(r.label)),
          ) &&
          !['categoria', 'categorie', 'voce'].contains(heading))
        return;
      result.add(
        ExpenseYearTable(
          year,
          rows,
          header.columns.keys.toList()..sort(),
          '${sheet.name}!${columnName(span.left)}${history ? firstRow : header.row}',
          wealth,
        ),
      );
    }

    // One year band may apply to several sections far below it. The monthly
    // category header and the history marker establish their own boundaries.
    for (final header in headers.where((h) => h.row >= 30)) {
      if (expenseLabel(
        sheet.at(header.row, span.left)?.text ?? '',
      ).contains('andamentopatrimonio'))
        continue;
      addTable(header, header.row + 1);
    }
    for (var row = band.row + 1; row <= endRow; row++) {
      if (!expenseLabel(
        sheet.at(row, span.left)?.text ?? '',
      ).contains('andamentopatrimonio'))
        continue;
      final previous = headers.where((h) => h.row <= row).toList();
      final canonical = previous
          .where(
            (h) =>
                h.row <= band.row + 5 ||
                result.any(
                  (t) =>
                      !t.wealth &&
                      t.year == year &&
                      t.reference ==
                          '${sheet.name}!${columnName(span.left)}${h.row}',
                ),
          )
          .toList();
      // History may repeat only some month labels. Keep the complete calendar
      // of its year/category table, including values under blank labels.
      if (previous.isNotEmpty)
        addTable(
          canonical.isEmpty ? previous.last : canonical.last,
          row + 1,
          history: true,
        );
    }
  }
  return result;
}

ExpenseData readExpenseData(
  ExpenseWorkbook workbook, {
  String sourceName = 'Excel OneDrive',
  DateTime? now,
}) {
  final total = workbook.sheet('2totale'), ledger = workbook.sheet('1spese');
  if (total == null || ledger == null)
    throw const FormatException('Servono i fogli “1- Spese” e “2- Totale”.');
  final warnings = <String>[];
  final lastLedgerRow = ledger.maxRow;
  double? field(List<String> names) {
    for (final cell in total.values.where((c) => c.row <= 38)) {
      if (!names.contains(expenseLabel(cell.text))) continue;
      final merge = total.mergeAt(cell.row, cell.column);
      for (
        var column = (merge?.right ?? cell.column) + 1;
        column <= (merge?.right ?? cell.column) + 3;
        column++
      ) {
        final candidate = total.at(cell.row, column);
        if (candidate?.number != null) return candidate!.number;
        if (candidate?.text.isNotEmpty == true) break;
      }
      return null;
    }
    return null;
  }

  final accounts = <String, double?>{
    'Conto principale': field(['contoprincipale']),
    'Sottoconto': field(['sottoconto']),
    'Conto deposito': field(['contodeposito']),
    'Portafoglio digitale': field(['portafogliodigitale']),
    'Conto investimenti': field(['contoinvestimenti']),
    'Conto secondario': field(['contosecondario']),
  };
  final liquids = field(['totaleliquidi']), pensionFund = field(['fondopensione']);
  final funds = <String, double?>{
    'Fondo Spese': field(['fondospese']),
    'Fondo Risparmi': field(['fondorisparmi']),
  };
  final factor = total.at(2, cellCoordinate('AF2').$2)?.number;
  final tables = _readExpenseTables(total);
  final transactions = <ExpenseTransaction>[], available = <String>{};
  final ledgerYears = ledger.values
      .where((c) => _tableHeaderYear(ledger, c) != null)
      .toList();
  final seenGroups = <String>{};
  for (final head in ledger.values.where((c) => c.row <= 18)) {
    if (head.value is DateTime && expenseYear(head.value) == null) continue;
    final month = expenseMonth(head.value);
    if (month == null) continue;
    final span = ledger.mergeAt(head.row, head.column);
    final start = span?.left ?? head.column;
    final yearBands =
        ledgerYears.where((y) {
          final m = ledger.mergeAt(y.row, y.column)!;
          return m.left <= start && m.right >= start;
        }).toList()..sort(
          (a, b) =>
              (a.row - head.row).abs().compareTo((b.row - head.row).abs()),
        );
    var year = head.value is DateTime
        ? expenseYear(head.value)
        : (head.value is String ? expenseYear(head.value) : null);
    if (yearBands.isNotEmpty) year = expenseYear(yearBands.first.value);
    var dateColumn = start,
        amountColumn = start + 2,
        descriptionColumn = start + 1,
        flagColumn = start + 3;
    final headerStart = math.max(
      head.row + 1,
      yearBands.isEmpty ? 0 : yearBands.first.row + 1,
    );
    var firstRow = headerStart;
    var hasDateHeader = false;
    for (
      var r = headerStart;
      r <= math.min(lastLedgerRow, headerStart + 12);
      r++
    ) {
      final labels = [
        for (var c = start; c <= (span?.right ?? start + 3); c++)
          expenseLabel(ledger.at(r, c)?.text ?? ''),
      ];
      final explicitDate = labels.any(
        (label) => label == 'data' || label == 'date',
      );
      final monthlyCategoryHeader =
          expenseMonth(ledger.at(r, start)?.value) == month &&
          labels.any((label) => label == 'categoria' || label == 'category');
      if (!explicitDate && !monthlyCategoryHeader) continue;
      hasDateHeader = true;
      firstRow = r + 1;
      for (var c = start; c <= (span?.right ?? start + 3); c++) {
        final label = expenseLabel(ledger.at(r, c)?.text ?? '');
        if (label == 'data' || label == 'date') {
          dateColumn = c;
          firstRow = math.max(firstRow, r + 1);
        }
        if (['importo', 'spese', 'spesa', 'valore', 'amount'].contains(label))
          amountColumn = c;
        if ([
          'descrizione',
          'descr',
          'description',
          'categoria',
          'category',
        ].contains(label))
          descriptionColumn = c;
        if (['conto', 'condiviso', 'tipo'].contains(label)) flagColumn = c;
      }
      break;
    }
    if ((span == null || head.value is DateTime) && !hasDateHeader) continue;
    // If a year heading is absent, use a real full date in this group's date
    // column; never derive a year from a payment amount or a day number.
    if (year == null) {
      for (var r = firstRow; r <= lastLedgerRow; r++) {
        final candidate = expenseDate(ledger.at(r, dateColumn)?.value);
        if (candidate != null &&
            expenseYear(candidate) != null &&
            candidate.month == month) {
          year = candidate.year;
          break;
        }
      }
    }
    if (year == null) continue;
    if (!seenGroups.add('$year:$month:$start')) continue;
    available.add(expenseMonthKey(DateTime(year, month)));
    for (var r = firstRow; r <= lastLedgerRow; r++) {
      final amount = ledger.at(r, amountColumn)?.number;
      if (amount == null) continue;
      final dateValue = ledger.at(r, dateColumn)?.value;
      final date = expenseDate(dateValue, year: year, month: month);
      if (date != null && (date.month != month || date.year != year)) continue;
      final transactionMonth = DateTime(year, month);
      available.add(expenseMonthKey(transactionMonth));
      final shared = ledger.at(r, flagColumn)?.text.trim().toUpperCase() == 'C';
      final adjusted = shared
          ? (factor == null || factor < 0 ? null : amount * factor)
          : amount;
      transactions.add(
        ExpenseTransaction(
          date ?? transactionMonth,
          ledger.at(r, descriptionColumn)?.text ?? '',
          amount,
          adjusted,
          shared,
          '${ledger.name}!${columnName(amountColumn)}$r',
          hasExactDate: date != null,
        ),
      );
    }
  }
  transactions.sort((a, b) => a.date.compareTo(b.date));
  final undated = transactions.where((t) => !t.hasExactDate).length;
  if (undated > 0) {
    warnings.add(
      '$undated operazioni senza data: incluse nei totali del mese indicato dalla colonna Excel, escluse dai grafici giornalieri.',
    );
  }
  if (liquids == null)
    warnings.add('Totale liquidi non disponibile nel foglio 2- Totale.');
  if (pensionFund == null) warnings.add('Valore Fondo pensione non disponibile.');
  if (tables.isEmpty)
    warnings.add(
      'Tabelle annuali non riconosciute: servono intestazioni anno e mesi.',
    );
  if (transactions.any((t) => t.amount == null))
    warnings.add(
      'Quota delle spese C non disponibile: controlla 2- Totale!AF2. I cumulati interessati restano incompleti.',
    );
  if (workbook.missingFormulaResults > 0)
    warnings.add(
      'Risultati formula non salvati: ${workbook.missingFormulaCells.take(6).join(', ')}. Salva l’Excel dopo il ricalcolo.',
    );
  if (workbook.formulaErrors.isNotEmpty)
    warnings.add(
      'Excel segnala un errore in ${workbook.formulaErrors.take(6).join(', ')}. I dati interessati restano non disponibili.',
    );
  return ExpenseData(
    accounts: accounts,
    liquids: liquids,
    pensionFund: pensionFund,
    funds: funds,
    sharedFactor: factor,
    tables: tables,
    transactions: transactions,
    availableMonths: available,
    warnings: warnings,
    loadedAt: now ?? DateTime.now(),
    sourceName: sourceName,
  );
}

DateTime? expenseDate(Object? value, {int? year, int? month}) {
  if (value is DateTime)
    return expenseYear(value) == null
        ? null
        : DateTime(value.year, value.month, value.day);
  if (value is num) {
    if (value > 20000 && value < 150000)
      return expenseDate(excelDate(value.toDouble()));
    if (year != null &&
        month != null &&
        value >= 1 &&
        value <= 31 &&
        value == value.round()) {
      final date = DateTime(year, month, value.toInt());
      return date.month == month ? date : null;
    }
  }
  if (value is String) {
    final iso = DateTime.tryParse(value);
    if (iso != null) return expenseDate(iso);
    final m = RegExp(
      r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2}|\d{4})$',
    ).firstMatch(value.trim());
    if (m != null) {
      final y = int.parse(m.group(3)!);
      final date = DateTime(
        y < 100 ? 2000 + y : y,
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
      );
      return expenseYear(date) != null &&
              date.month == int.parse(m.group(2)!) &&
              date.day == int.parse(m.group(1)!)
          ? date
          : null;
    }
  }
  return null;
}
