import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../markets/presentation/finance_widgets.dart';
import '../domain/expense_workbook.dart';

class ExpenseYearTableView extends StatefulWidget {
  const ExpenseYearTableView({
    required this.table,
    this.filter = '',
    super.key,
  });
  final ExpenseYearTable table;
  final String filter;
  @override
  State<ExpenseYearTableView> createState() => _ExpenseYearTableViewState();
}

class _ExpenseYearTableViewState extends State<ExpenseYearTableView> {
  final _horizontal = ScrollController();
  static const _rowHeight = 42.0;
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  bool _total(ExpenseTableRow row) => expenseLabel(row.label).startsWith('tot');
  Widget _cell(
    String text, {
    bool number = false,
    bool heading = false,
    bool total = false,
    bool alternate = false,
    String? tooltip,
  }) => Container(
    height: _rowHeight,
    alignment: number ? Alignment.centerRight : Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: heading || total
          ? AppColors.greenSoft
          : alternate
          ? const Color(0xFFF6F9F8)
          : Colors.white,
      border: const Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Tooltip(
      message: tooltip ?? text,
      child: Text(
        text,
        maxLines: number ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        textAlign: number ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 12,
          fontWeight: heading || total ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final rows = table.rows
        .where(
          (r) => r.label.toLowerCase().contains(widget.filter.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${table.year} · ${rows.length} voci · Importi in EUR',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nessuna categoria corrispondente.'),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final categoryWidth = math.min(
                220.0,
                math.max(80.0, box.maxWidth * .28),
              );
              final monthWidth = math.max(
                104.0,
                (box.maxWidth - categoryWidth) /
                    math.max(1, table.months.length),
              );
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: (rows.length + 1) * _rowHeight + 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category names stay visible when scrolling through the months.
                      SizedBox(
                        width: categoryWidth,
                        child: Column(
                          children: [
                            _cell('Categoria', heading: true),
                            for (var i = 0; i < rows.length; i++)
                              _cell(
                                rows[i].label,
                                total: _total(rows[i]),
                                alternate: i.isOdd,
                                tooltip:
                                    '${rows[i].label}\n${rows[i].reference}',
                              ),
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
                            thumbVisibility: true,
                            trackVisibility: true,
                            interactive: true,
                            child: SingleChildScrollView(
                              controller: _horizontal,
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      for (final month in table.months)
                                        SizedBox(
                                          width: monthWidth,
                                          child: _cell(
                                            expenseMonths[month - 1],
                                            number: true,
                                            heading: true,
                                          ),
                                        ),
                                    ],
                                  ),
                                  for (var i = 0; i < rows.length; i++)
                                    Row(
                                      children: [
                                        for (final month in table.months)
                                          SizedBox(
                                            width: monthWidth,
                                            child: _cell(
                                              amount(
                                                rows[i].values[month],
                                                currency: '',
                                              ),
                                              number: true,
                                              total: _total(rows[i]),
                                              alternate: i.isOdd,
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
