import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../markets/presentation/finance_widgets.dart';
import '../domain/expense_workbook.dart';
import 'expense_dashboard_widgets.dart';

enum AnnualTableSort { source, totalDescending, totalAscending, category }

/// Sum source columns once. Missing cells remain unknown, not zero.
double? annualRowTotal(ExpenseYearTable table, ExpenseTableRow row) {
  if (table.months.isEmpty || table.months.any((m) => row.values[m] == null)) {
    return null;
  }
  return table.months.fold<double>(0, (sum, m) => sum + row.values[m]!);
}

bool _aggregate(ExpenseTableRow row) =>
    expenseLabel(row.label).startsWith('tot');
bool _refund(ExpenseTableRow row) =>
    expenseLabel(row.label).startsWith('rimbors');
bool _monthlyTotal(ExpenseTableRow row) => const [
  'totspese',
  'totalespese',
  'totalemensile',
].contains(expenseLabel(row.label));

class ExpenseAnnualReport extends StatefulWidget {
  const ExpenseAnnualReport({
    required this.data,
    required this.year,
    required this.onYearChanged,
    super.key,
  });
  final ExpenseData? data;
  final int year;
  final ValueChanged<int> onYearChanged;
  @override
  State<ExpenseAnnualReport> createState() => _ExpenseAnnualReportState();
}

class _ExpenseAnnualReportState extends State<ExpenseAnnualReport> {
  String _filter = '';
  int _digits = 2;
  AnnualTableSort _sort = AnnualTableSort.source;
  @override
  Widget build(BuildContext context) {
    final data = widget.data, year = widget.year;
    final years = {
      if (data != null) ...data.tables.map((t) => t.year),
      year,
    }.toList()..sort();
    final index = years.indexOf(year);
    final tables =
        data?.tables.where((t) => !t.wealth && t.year == year).toList() ??
        <ExpenseYearTable>[];
    final records =
        data?.transactions.where((t) => t.date.year == year).toList() ??
        <ExpenseTransaction>[];
    final total = _sum(records);
    final months = records.map((t) => t.date.month).toSet();
    final average = total == null ? null : total / math.max(1, months.length);
    final allCategories = {
      for (final t in tables)
        for (final row in t.rows)
          if (!_aggregate(row) && !_refund(row)) row.label,
    };
    final visibleCategories = allCategories
        .where((name) => name.toLowerCase().contains(_filter.toLowerCase()))
        .length;
    // Compare the same observed calendar months and days, never a partial year
    // against a complete previous year or a static demonstration percentage.
    final now = DateTime.now();
    final read = data?.loadedAt ?? now;
    final asOf = read.isBefore(now) ? read : now;
    final completeYear = year < asOf.year;
    final previousEnd = completeYear
        ? DateTime(year - 1, 12, 31)
        : DateTime(
            year - 1,
            asOf.month,
            math.min(asOf.day, DateTime(year - 1, asOf.month + 1, 0).day),
          );
    final previous =
        data?.transactions
            .where(
              (t) =>
                  t.date.year == year - 1 &&
                  months.contains(t.date.month) &&
                  t.date.isBefore(previousEnd.add(const Duration(days: 1))),
            )
            .toList() ??
        <ExpenseTransaction>[];
    final previousMonths = previous.map((t) => t.date.month).toSet();
    final comparable =
        year <= asOf.year &&
        months.isNotEmpty &&
        records.every((t) => t.hasExactDate) &&
        previous.every((t) => t.hasExactDate) &&
        records.every(
          (t) =>
              completeYear ||
              t.date.isBefore(DateTime(year, asOf.month, asOf.day + 1)),
        ) &&
        months.every(previousMonths.contains);
    final previousTotal = comparable ? _sum(previous) : null;
    double? change(double? current, double? before) =>
        current == null || before == null || before == 0
        ? null
        : (current - before) / before.abs() * 100;
    return ExpensePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final selector = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _control(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 17,
                          color: expenseMuted,
                        ),
                        const SizedBox(width: 15),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: year,
                            isDense: true,
                            style: _text(12, color: AppColors.text),
                            icon: const Padding(
                              padding: EdgeInsets.only(left: 26),
                              child: Icon(
                                Icons.expand_more,
                                size: 17,
                                color: expenseMuted,
                              ),
                            ),
                            items: [
                              for (final y in years)
                                DropdownMenuItem(value: y, child: Text('$y')),
                            ],
                            onChanged: (value) {
                              if (value != null) widget.onYearChanged(value);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Anno precedente',
                    onPressed: index > 0
                        ? () => widget.onYearChanged(years[index - 1])
                        : null,
                    icon: const Icon(Icons.chevron_left, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Anno successivo',
                    onPressed: index < years.length - 1
                        ? () => widget.onYearChanged(years[index + 1])
                        : null,
                    icon: const Icon(Icons.chevron_right, size: 20),
                  ),
                ],
              );
              final heading = Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF8F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: AppColors.green,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Riepilogo annuale',
                          style: _text(
                            20,
                            weight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Categorie e confronto mese per mese · valori della fonte Excel',
                          style: _text(12),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              return box.maxWidth >= 750
                  ? Row(
                      children: [
                        Expanded(child: heading),
                        selector,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [heading, const SizedBox(height: 12), selector],
                    );
            },
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 1000
                  ? 4
                  : box.maxWidth >= 530
                  ? 2
                  : 1;
              final width = (box.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _kpi(
                    width,
                    'Operazioni registrate $year',
                    amount(total),
                    Icons.receipt_long_outlined,
                    change(total, previousTotal),
                    year - 1,
                  ),
                  _kpi(
                    width,
                    'Media mensile registrata',
                    amount(average),
                    Icons.bar_chart,
                    change(
                      average,
                      previousTotal == null
                          ? null
                          : previousTotal / months.length,
                    ),
                    year - 1,
                  ),
                  _kpi(
                    width,
                    'Numero operazioni',
                    '${records.length}',
                    Icons.storage_outlined,
                    comparable
                        ? change(
                            records.length.toDouble(),
                            previous.length.toDouble(),
                          )
                        : null,
                    year - 1,
                  ),
                  _kpi(
                    width,
                    'Categorie analizzate',
                    '$visibleCategories',
                    Icons.pie_chart_outline,
                    null,
                    year - 1,
                    caption: 'su ${allCategories.length} disponibili',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              final search = SizedBox(
                height: 41,
                child: TextField(
                  onChanged: (value) => setState(() => _filter = value),
                  style: _text(12),
                  decoration: InputDecoration(
                    hintText: 'Filtra categorie della tabella',
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 20,
                      color: expenseMuted,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    filled: false,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              );
              final controls = Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _control(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.payments_outlined,
                          size: 16,
                          color: expenseMuted,
                        ),
                        const SizedBox(width: 10),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _digits,
                            isDense: true,
                            style: _text(11, color: AppColors.text),
                            icon: const Padding(
                              padding: EdgeInsets.only(left: 13),
                              child: Icon(
                                Icons.expand_more,
                                size: 16,
                                color: expenseMuted,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 2,
                                child: Text('Valori in EUR'),
                              ),
                              DropdownMenuItem(
                                value: 0,
                                child: Text('EUR · arrotondati'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _digits = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  _control(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.swap_vert,
                          size: 17,
                          color: expenseMuted,
                        ),
                        const SizedBox(width: 9),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<AnnualTableSort>(
                            value: _sort,
                            isDense: true,
                            style: _text(11, color: AppColors.text),
                            icon: const Padding(
                              padding: EdgeInsets.only(left: 12),
                              child: Icon(
                                Icons.expand_more,
                                size: 16,
                                color: expenseMuted,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: AnnualTableSort.source,
                                child: Text('Ordine della fonte'),
                              ),
                              DropdownMenuItem(
                                value: AnnualTableSort.totalDescending,
                                child: Text('Totale decrescente'),
                              ),
                              DropdownMenuItem(
                                value: AnnualTableSort.totalAscending,
                                child: Text('Totale crescente'),
                              ),
                              DropdownMenuItem(
                                value: AnnualTableSort.category,
                                child: Text('Categoria A–Z'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) setState(() => _sort = value);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              return box.maxWidth > 850
                  ? Row(
                      children: [
                        Expanded(child: search),
                        const SizedBox(width: 12),
                        controls,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [search, const SizedBox(height: 10), controls],
                    );
            },
          ),
          const SizedBox(height: 16),
          if (tables.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Riepilogo annuale non disponibile.'),
            ),
          for (final table in tables)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ExpenseAnnualTable(
                key: ValueKey(table.reference),
                table: table,
                filter: _filter,
                sort: _sort,
                digits: _digits,
                transactions: records,
              ),
            ),
        ],
      ),
    );
  }

  double? _sum(List<ExpenseTransaction> records) =>
      records.isEmpty || records.any((t) => t.amount == null)
      ? null
      : records.fold<double>(0, (sum, t) => sum + t.amount!);
  Widget _control({required Widget child}) => Container(
    height: 41,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Center(widthFactor: 1, child: child),
  );
  Widget _kpi(
    double width,
    String title,
    String value,
    IconData icon,
    double? delta,
    int previousYear, {
    String? caption,
  }) => Container(
    width: width,
    height: usesPhoneLayout(context)
        ? 140 * MediaQuery.textScalerOf(context).scale(1)
        : 105,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(12),
      gradient: const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFFCFEFD)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 47,
          height: 47,
          decoration: BoxDecoration(
            color: const Color(0xFFEAFAF2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: AppColors.green),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: _text(12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: _text(
                    22,
                    weight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              if (caption != null)
                Text(caption, style: _text(10))
              else
                Tooltip(
                  message:
                      'Confronto con gli stessi mesi e giorni disponibili del $previousYear.',
                  child: Row(
                    children: [
                      if (delta != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE4F9EC),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                delta >= 0 ? Icons.north : Icons.south,
                                size: 11,
                                color: AppColors.green,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)}%',
                                style: _text(
                                  10,
                                  color: AppColors.green,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (delta != null) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          delta == null
                              ? 'Confronto non disponibile'
                              : 'rispetto al $previousYear',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _text(10),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

TextStyle _text(
  double size, {
  Color color = expenseMuted,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: 1.25,
  fontFamily: 'Segoe UI Variable',
  fontFamilyFallback: const ['Segoe UI', 'Arial', 'sans-serif'],
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// Annual-only table. The existing wealth-history table is intentionally separate.
class ExpenseAnnualTable extends StatefulWidget {
  const ExpenseAnnualTable({
    required this.table,
    this.filter = '',
    this.sort = AnnualTableSort.source,
    this.digits = 2,
    this.transactions = const [],
    super.key,
  });
  final ExpenseYearTable table;
  final String filter;
  final AnnualTableSort sort;
  final int digits;
  final List<ExpenseTransaction> transactions;
  @override
  State<ExpenseAnnualTable> createState() => _ExpenseAnnualTableState();
}

class _ExpenseAnnualTableState extends State<ExpenseAnnualTable> {
  final _horizontal = ScrollController();
  int? _monthSort;
  bool _ascending = false, _categorySort = false;
  static const _rowHeight = 40.0, _headerHeight = 44.0, _footerHeight = 56.0;
  @override
  void didUpdateWidget(covariant ExpenseAnnualTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sort != widget.sort) {
      _monthSort = null;
      _categorySort = false;
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  int _compare(double? a, double? b, bool ascending) => a == null
      ? (b == null ? 0 : 1)
      : b == null
      ? -1
      : ascending
      ? a.compareTo(b)
      : b.compareTo(a);
  List<ExpenseTableRow> _rows({bool reimbursements = false}) {
    final indexed = widget.table.rows.indexed
        .where(
          (r) =>
              !_aggregate(r.$2) &&
              _refund(r.$2) == reimbursements &&
              r.$2.label.toLowerCase().contains(
                widget.filter.trim().toLowerCase(),
              ),
        )
        .toList();
    indexed.sort((a, b) {
      final first = a.$2, second = b.$2;
      final result = _monthSort == 0
          ? _compare(
              annualRowTotal(widget.table, first),
              annualRowTotal(widget.table, second),
              _ascending,
            )
          : _monthSort != null
          ? _compare(
              first.values[_monthSort],
              second.values[_monthSort],
              _ascending,
            )
          : _categorySort
          ? (_ascending ? 1 : -1) *
                first.label.toLowerCase().compareTo(second.label.toLowerCase())
          : switch (widget.sort) {
              AnnualTableSort.source => a.$1.compareTo(b.$1),
              AnnualTableSort.category => first.label.toLowerCase().compareTo(
                second.label.toLowerCase(),
              ),
              AnnualTableSort.totalDescending => _compare(
                annualRowTotal(widget.table, first),
                annualRowTotal(widget.table, second),
                false,
              ),
              AnnualTableSort.totalAscending => _compare(
                annualRowTotal(widget.table, first),
                annualRowTotal(widget.table, second),
                true,
              ),
            };
      return result != 0 ? result : a.$1.compareTo(b.$1);
    });
    return indexed.map((r) => r.$2).toList();
  }

  ExpenseTableRow _footer() {
    for (final row in widget.table.rows) {
      if (_monthlyTotal(row)) {
        return row;
      }
    }
    // No source aggregate: use the actual ledger, never add category rows that
    // may themselves contain subtotals or refund adjustments.
    return ExpenseTableRow('Totale mensile', {
      for (final month in widget.table.months) month: _ledgerMonth(month),
    }, '1- Spese · operazioni registrate');
  }

  double? _ledgerMonth(int month) {
    final records = widget.transactions
        .where((t) => t.date.year == widget.table.year && t.date.month == month)
        .toList();
    return records.isEmpty || records.any((t) => t.amount == null)
        ? null
        : records.fold<double>(0, (sum, t) => sum + t.amount!);
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table, rows = _rows(), footer = _footer();
    final refunds = _rows(reimbursements: true);
    final summaries = [
      ExpenseTableRow('Totale mensile', footer.values, footer.reference),
      for (final row in table.rows.where(
        (row) => _aggregate(row) && !_monthlyTotal(row),
      ))
        ExpenseTableRow(
          expenseLabel(row.label).contains('nettoinvest')
              ? 'Totale netto investimenti'
              : row.label,
          row.values,
          row.reference,
        ),
    ];
    final yearTotal = annualRowTotal(table, footer);
    final magnitudes = [
      for (final row in table.rows)
        if (!_aggregate(row))
          for (final value in row.values.values)
            if (value != null) value.abs(),
    ];
    final max = magnitudes.isEmpty
        ? 1.0
        : math.max(1.0, magnitudes.reduce(math.max));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final categoryWidth = box.maxWidth >= 1100
                ? 200.0
                : box.maxWidth >= 600
                ? 175.0
                : 128.0;
            const totalWidth = 126.0, shareWidth = 98.0, trendWidth = 154.0;
            final monthWidth = math.max(
              84.0,
              (box.maxWidth -
                      categoryWidth -
                      totalWidth -
                      shareWidth -
                      trendWidth -
                      2) /
                  12,
            );
            final numericWidth =
                monthWidth * 12 + totalWidth + shareWidth + trendWidth;
            final scrolls = numericWidth > box.maxWidth - categoryWidth;
            final height =
                _headerHeight +
                rows.length * _rowHeight +
                (refunds.isEmpty ? 0 : 12 + 36 + refunds.length * _rowHeight) +
                12 +
                summaries.length * _footerHeight +
                (scrolls ? 14 : 0);
            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: height,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: categoryWidth,
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: Column(
                          children: [
                            _categoryHeader(),
                            for (var i = 0; i < rows.length; i++)
                              _category(rows[i], i.isOdd),
                            if (refunds.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _refundHeading(),
                              for (var i = 0; i < refunds.length; i++)
                                _category(refunds[i], i.isOdd),
                            ],
                            const SizedBox(height: 12),
                            for (final row in summaries) _categoryFooter(row),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          child: Scrollbar(
                            controller: _horizontal,
                            thumbVisibility: scrolls,
                            trackVisibility: scrolls,
                            interactive: true,
                            child: SingleChildScrollView(
                              controller: _horizontal,
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.only(
                                bottom: scrolls ? 14 : 0,
                              ),
                              child: SizedBox(
                                width: numericWidth,
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        for (var m = 1; m <= 12; m++)
                                          SizedBox(
                                            width: monthWidth,
                                            child: _header(
                                              expenseMonths[m - 1],
                                              onTap: () => setState(() {
                                                _ascending = _monthSort == m
                                                    ? !_ascending
                                                    : false;
                                                _monthSort = m;
                                                _categorySort = false;
                                              }),
                                              active: _monthSort == m,
                                            ),
                                          ),
                                        SizedBox(
                                          width: totalWidth,
                                          child: _header(
                                            'Totale ${table.year}',
                                            bold: true,
                                            onTap: () => setState(() {
                                              _ascending = _monthSort == 0
                                                  ? !_ascending
                                                  : false;
                                              _monthSort = 0;
                                              _categorySort = false;
                                            }),
                                            active: _monthSort == 0,
                                          ),
                                        ),
                                        SizedBox(
                                          width: shareWidth,
                                          child: _header('% sul totale'),
                                        ),
                                        SizedBox(
                                          width: trendWidth,
                                          child: _header(
                                            'Trend mensile',
                                            center: false,
                                          ),
                                        ),
                                      ],
                                    ),
                                    for (var i = 0; i < rows.length; i++)
                                      _numbers(
                                        rows[i],
                                        monthWidth,
                                        totalWidth,
                                        trendWidth,
                                        max,
                                        i.isOdd,
                                        yearTotal: yearTotal,
                                      ),
                                    if (refunds.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        height: 36,
                                        color: const Color(0xFFF2F2F4),
                                      ),
                                      for (var i = 0; i < refunds.length; i++)
                                        _numbers(
                                          refunds[i],
                                          monthWidth,
                                          totalWidth,
                                          trendWidth,
                                          max,
                                          i.isOdd,
                                          yearTotal: yearTotal,
                                        ),
                                    ],
                                    const SizedBox(height: 12),
                                    for (final row in summaries)
                                      _numbers(
                                        row,
                                        monthWidth,
                                        totalWidth,
                                        trendWidth,
                                        max,
                                        false,
                                        footer: true,
                                        yearTotal: yearTotal,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 9),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 14,
          runSpacing: 6,
          children: [
            Text(
              '${table.year} · ${rows.length + refunds.length + summaries.length} voci · Importi in EUR',
              style: _text(10),
            ),
            Text(
              widget.filter.isEmpty
                  ? 'Intensità delle celle: importo per mese · clic sulle intestazioni per ordinare'
                  : 'Filtro su ${rows.length + refunds.length} voci · i riepiloghi restano quelli generali della fonte',
              style: _text(10),
            ),
          ],
        ),
        if (rows.isEmpty && refunds.isEmpty)
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text('Nessuna categoria corrispondente.', style: _text(12)),
          ),
      ],
    );
  }

  Widget _categoryHeader() => InkWell(
    onTap: () => setState(() {
      _ascending = _categorySort ? !_ascending : true;
      _categorySort = true;
      _monthSort = null;
    }),
    child: Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: const Color(0xFFF5F5F7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Categoria',
              style: _text(
                13,
                weight: FontWeight.w600,
                color: const Color(0xFF3C5370),
              ),
            ),
          ),
          Icon(
            _categorySort && !_ascending
                ? Icons.sort_by_alpha
                : Icons.filter_list,
            size: 15,
            color: expenseMuted,
          ),
        ],
      ),
    ),
  );
  Widget _category(ExpenseTableRow row, bool alternate) {
    final (icon, color) = expenseCategoryStyle(row.label);
    final education = expenseLabel(row.label).startsWith('istruzion');
    return Tooltip(
      message: '${row.label}\n${row.reference}',
      child: Container(
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _aggregate(row)
              ? const Color(0xFFF0F8F4)
              : alternate
              ? const Color(0xFFFAFAFC)
              : Colors.white,
          border: const Border(bottom: BorderSide(color: Color(0xFFF2F2F4))),
        ),
        child: Row(
          children: [
            Container(
              width: 25,
              height: 25,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(7),
              ),
              child: education
                  ? const Text(
                      '🎓',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1,
                        fontFamily: 'Segoe UI Emoji',
                      ),
                    )
                  : Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                row.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _text(
                  13,
                  weight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refundHeading() => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    color: const Color(0xFFF2F2F4),
    child: Row(
      children: [
        const Icon(Icons.undo_rounded, size: 17, color: expenseBlue),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Rimborsi',
            style: _text(12, weight: FontWeight.w600, color: AppColors.text),
          ),
        ),
      ],
    ),
  );
  Widget _categoryFooter(ExpenseTableRow source) => Tooltip(
    message:
        'Totale della fonte: ${source.label}\n${source.reference}\nI sottototali non vengono sommati nuovamente.',
    child: Container(
      height: _footerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF2FAF6),
        border: Border(top: BorderSide(color: Color(0xFFDCEFE6))),
      ),
      child: Row(
        children: [
          const Icon(Icons.bar_chart_rounded, size: 19, color: AppColors.green),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              source.label,
              style: _text(12, color: AppColors.text, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _header(
    String label, {
    VoidCallback? onTap,
    bool bold = false,
    bool active = false,
    bool center = true,
  }) => InkWell(
    onTap: onTap,
    child: Container(
      height: _headerHeight,
      alignment: center ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F7),
        border: Border(left: BorderSide(color: Color(0xFFF2F2F4))),
      ),
      child: Row(
        mainAxisAlignment: center
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(
                bold ? 13 : 12,
                weight: bold ? FontWeight.w700 : FontWeight.w600,
                color: bold ? AppColors.text : const Color(0xFF3C5370),
              ),
            ),
          ),
          if (active)
            Icon(
              _ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 12,
              color: AppColors.green,
            ),
        ],
      ),
    ),
  );
  Widget _numbers(
    ExpenseTableRow row,
    double monthWidth,
    double totalWidth,
    double trendWidth,
    double max,
    bool alternate, {
    bool footer = false,
    required double? yearTotal,
  }) {
    final total = annualRowTotal(widget.table, row),
        aggregate = _aggregate(row);
    final share = total == null || yearTotal == null || yearTotal == 0
        ? null
        : total / yearTotal * 100;
    final color = footer ? AppColors.green : expenseCategoryStyle(row.label).$2;
    return Row(
      children: [
        for (var month = 1; month <= 12; month++)
          SizedBox(
            width: monthWidth,
            child: _value(
              row.values[month],
              max,
              alternate,
              aggregate: aggregate,
              footer: footer,
              tooltip:
                  '${row.label} · ${expenseMonths[month - 1]} ${widget.table.year}\n${amount(row.values[month])}\n${row.reference}',
            ),
          ),
        SizedBox(
          width: totalWidth,
          child: _value(
            total,
            max,
            alternate,
            total: true,
            footer: footer,
            tooltip:
                '${row.label} · totale ${widget.table.year}\n${amount(total)}\nSomma delle colonne disponibili; le celle mancanti restano non disponibili.',
          ),
        ),
        SizedBox(
          width: 98,
          child: _value(
            share,
            1,
            alternate,
            total: true,
            footer: footer,
            displayText: share == null
                ? '—'
                : '${share.toStringAsFixed(1).replaceAll('.', ',')}%',
            tooltip:
                '${row.label} · quota sul totale annuo della fonte\n${amount(total)} / ${amount(yearTotal)}\nIl denominatore non cambia con il filtro categorie.',
          ),
        ),
        SizedBox(
          width: trendWidth,
          height: footer ? _footerHeight : _rowHeight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: footer
                  ? const Color(0xFFF2FAF6)
                  : alternate
                  ? const Color(0xFFFAFAFC)
                  : Colors.white,
              border: Border(
                bottom: const BorderSide(color: Color(0xFFF2F2F4)),
                top: footer
                    ? const BorderSide(color: Color(0xFFDCEFE6))
                    : BorderSide.none,
              ),
            ),
            child: Tooltip(
              message: [
                for (var m = 1; m <= 12; m++)
                  '${expenseMonths[m - 1]}: ${amount(row.values[m])}',
              ].join('\n'),
              child: CustomPaint(
                painter: _AnnualBars([
                  for (var m = 1; m <= 12; m++) row.values[m],
                ], color),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _value(
    double? value,
    double max,
    bool alternate, {
    bool aggregate = false,
    bool total = false,
    bool footer = false,
    String? displayText,
    required String tooltip,
  }) {
    final base = alternate ? const Color(0xFFFAFCFB) : Colors.white;
    final heat = value == null || value == 0 || aggregate
        ? base
        : Color.lerp(
            base,
            value < 0 ? const Color(0xFFD7EBF9) : const Color(0xFFBBEDDB),
            math.sqrt(value.abs() / max).clamp(0, 1),
          )!;
    return Tooltip(
      message: tooltip,
      child: Container(
        height: footer ? _footerHeight : _rowHeight,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: footer
              ? const Color(0xFFF2FAF6)
              : total
              ? const Color(0xFFF5FAF7)
              : aggregate
              ? const Color(0xFFF2F8F5)
              : heat,
          border: Border(
            left: const BorderSide(color: Color(0x55FFFFFF)),
            bottom: const BorderSide(color: Color(0xFFF2F2F4)),
            top: footer
                ? const BorderSide(color: Color(0xFFDCEFE6))
                : BorderSide.none,
          ),
        ),
        child: Text(
          displayText ?? amount(value, currency: '', digits: widget.digits),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _text(
            total || footer ? 14 : 13,
            weight: total || footer || aggregate
                ? FontWeight.w700
                : FontWeight.w400,
            color: total || footer
                ? AppColors.text
                : value == null || value == 0
                ? expenseMuted
                : const Color(0xFF38666C),
          ),
        ),
      ),
    );
  }
}

class _AnnualBars extends CustomPainter {
  _AnnualBars(this.values, this.color);
  final List<double?> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final max = math.max(
      1.0,
      values.whereType<double>().map((v) => v.abs()).fold<double>(0, math.max),
    );
    final width = size.width / 12, baseline = size.height - 1;
    for (var i = 0; i < values.length; i++) {
      final barWidth = math.max(2.0, width - 3);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * width, 3, barWidth, math.max(1, baseline - 3)),
        const Radius.circular(1),
      );
      canvas.drawRRect(rect, Paint()..color = const Color(0xFFEDEDF0));
      final v = values[i];
      if (v == null || v == 0) continue;
      final height = math.max(2.0, v.abs() / max * (baseline - 3));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * width, baseline - height, barWidth, height),
          const Radius.circular(1),
        ),
        Paint()..color = v < 0 ? color.withValues(alpha: .5) : color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnnualBars old) =>
      old.values != values || old.color != color;
}
