import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../markets/presentation/finance_widgets.dart';
import '../domain/expense_summary.dart';
import '../domain/expense_workbook.dart';
import 'expense_dashboard_widgets.dart';

class ExpenseTransactions extends StatefulWidget {
  const ExpenseTransactions({
    required this.transactions,
    required this.month,
    this.factor,
    super.key,
  });
  final List<ExpenseTransaction> transactions;
  final DateTime month;
  final double? factor;
  @override
  State<ExpenseTransactions> createState() => ExpenseTransactionsState();
}

class ExpenseTransactionsState extends State<ExpenseTransactions> {
  String _dateLabel(ExpenseTransaction t) =>
      t.hasExactDate ? dayLabel(t.date) : 'Senza data';
  void showUndated() => setState(() {
    _search.text = 'Senza data';
    _allHistory = false;
    _category = null;
    _shared = null;
    _dates = null;
    _page = 0;
  });
  final _search = TextEditingController(), _horizontal = ScrollController();
  String? _category;
  bool? _shared;
  bool _allHistory = false, _ascending = false, _sortAmount = false;
  DateTimeRange? _dates;
  int _page = 0;
  static const _pageSize = 10;
  void selectCategory(String category) => setState(() {
    _category = category;
    _page = 0;
  });
  @override
  void didUpdateWidget(covariant ExpenseTransactions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) {
      _page = 0;
      _dates = null;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _filters() async {
    var category = _category,
        shared = _shared,
        history = _allHistory,
        dates = _dates;
    final categories =
        widget.transactions.map((t) => t.description).toSet().toList()..sort();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          insetPadding: usesPhoneLayout(ctx)
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 20)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          title: const Text('Filtra transazioni'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Storico completo'),
                    subtitle: Text(
                      history
                          ? 'Tutti i mesi presenti nell’Excel'
                          : expenseLongMonth(widget.month),
                    ),
                    value: history,
                    onChanged: (v) => update(() => history = v),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(category),
                    initialValue: category,
                    isExpanded: true,
                    hint: const Text('Tutte le categorie'),
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Tutte le categorie'),
                      ),
                      for (final c in categories)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => update(() => category = v),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    key: ValueKey(shared),
                    initialValue: shared == null
                        ? 0
                        : shared!
                        ? 2
                        : 1,
                    decoration: const InputDecoration(labelText: 'Conto'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Tutti')),
                      DropdownMenuItem(value: 1, child: Text('Personale')),
                      DropdownMenuItem(value: 2, child: Text('Condiviso C')),
                    ],
                    onChanged: (v) =>
                        update(() => shared = v == 0 ? null : v == 2),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      dates == null
                          ? 'Intervallo date'
                          : '${dayLabel(dates!.start)} – ${dayLabel(dates!.end)}',
                    ),
                    onPressed: () async {
                      final ordered = widget.transactions.toList()
                        ..sort((a, b) => a.date.compareTo(b.date));
                      if (ordered.isEmpty) return;
                      final range = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(ordered.first.date.year),
                        lastDate: DateTime(ordered.last.date.year + 1),
                        initialDateRange: dates,
                      );
                      if (range != null) {
                        update(() {
                          dates = range;
                          history = true;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => update(() {
                category = null;
                shared = null;
                dates = null;
                history = false;
              }),
              child: const Text('Azzera'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Applica'),
            ),
          ],
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() {
        _category = category;
        _shared = shared;
        _allHistory = history;
        _dates = dates;
        _page = 0;
      });
    }
  }

  void _clear() => setState(() {
    _category = null;
    _shared = null;
    _dates = null;
    _allHistory = false;
    _search.clear();
    _page = 0;
  });
  void _details(ExpenseTransaction t) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.description),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.hasExactDate
                ? dayLabel(t.date)
                : 'Senza data · ${expenseLongMonth(t.date)}',
          ),
          const SizedBox(height: 14),
          Text('Importo originale: ${amount(t.originalAmount)}'),
          Text('Quota nelle spese: ${amount(t.amount)}'),
          Text('Conto: ${t.shared ? 'Condiviso C' : 'Personale'}'),
          if (t.shared)
            Text(
              'Parametro C: ${widget.factor ?? 'non disponibile'} · 2- Totale!AF2',
            ),
          const SizedBox(height: 14),
          SelectableText(
            t.reference,
            style: const TextStyle(fontSize: 12, color: expenseMuted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final rows =
        widget.transactions
            .where(
              (t) =>
                  (_allHistory ||
                      (t.date.year == widget.month.year &&
                          t.date.month == widget.month.month)) &&
                  (_category == null || t.description == _category) &&
                  (_shared == null || t.shared == _shared) &&
                  (_dates == null ||
                      (t.hasExactDate &&
                          !t.date.isBefore(_dates!.start) &&
                          t.date.isBefore(
                            _dates!.end.add(const Duration(days: 1)),
                          ))) &&
                  (query.isEmpty ||
                      '${t.description} ${_dateLabel(t)} ${expenseLongMonth(t.date)} ${t.shared ? 'Condiviso C' : 'Personale'} ${t.reference}'
                          .toLowerCase()
                          .contains(query)),
            )
            .toList()
          ..sort((a, b) {
            if (!_sortAmount && a.hasExactDate != b.hasExactDate) {
              return a.hasExactDate ? -1 : 1;
            }
            final value = _sortAmount
                ? (a.amount ?? double.negativeInfinity).compareTo(
                    b.amount ?? double.negativeInfinity,
                  )
                : a.date.compareTo(b.date);
            return _ascending ? value : -value;
          });
    final pages = math.max(1, (rows.length / _pageSize).ceil());
    final page = _page.clamp(0, pages - 1);
    final visible = rows.skip(page * _pageSize).take(_pageSize);
    final filterCount =
        (_category == null ? 0 : 1) +
        (_shared == null ? 0 : 1) +
        (_dates == null ? 0 : 1);
    return ExpensePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final toolItems = <Widget>[
                SizedBox(
                  width: usesPhoneLayout(context)
                      ? box.maxWidth
                      : box.maxWidth > 750
                      ? 235
                      : math.min(210, math.max(75, box.maxWidth - 180)),
                  height: usesPhoneLayout(context) ? 44 : 33,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() => _page = 0),
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      hintText: 'Cerca transazioni…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 35),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      filled: false,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: usesPhoneLayout(context) ? 44 : 33,
                  child: OutlinedButton.icon(
                    onPressed: _filters,
                    icon: const Icon(Icons.filter_list, size: 17),
                    label: Text(
                      filterCount == 0 ? 'Filtra' : 'Filtra ($filterCount)',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opzioni transazioni',
                  icon: const Icon(Icons.more_horiz, size: 21),
                  onSelected: (value) {
                    if (value == 'reset') {
                      _clear();
                    } else {
                      setState(() {
                        _allHistory = value == 'all';
                        _dates = null;
                        _page = 0;
                      });
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'all',
                      child: Text('Mostra storico completo'),
                    ),
                    const PopupMenuItem(
                      value: 'month',
                      child: Text('Mostra mese selezionato'),
                    ),
                    const PopupMenuItem(
                      value: 'reset',
                      child: Text('Azzera ricerca e filtri'),
                    ),
                  ],
                ),
              ];
              final tools = usesPhoneLayout(context)
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: toolItems
                          .where((w) => w is! SizedBox || w.height != null)
                          .toList(),
                    )
                  : Row(mainAxisSize: MainAxisSize.min, children: toolItems);
              final heading = ExpenseHeading(
                'Ultime transazioni',
                Icons.format_list_bulleted,
                action: box.maxWidth > 750 && !usesPhoneLayout(context)
                    ? tools
                    : null,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  if (box.maxWidth <= 750 || usesPhoneLayout(context)) ...[
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: tools),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (_allHistory || filterCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (_allHistory)
                    const Chip(
                      label: Text(
                        'Storico completo',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  if (_category != null)
                    InputChip(
                      label: Text(
                        _category!,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onDeleted: () => setState(() => _category = null),
                    ),
                  if (_shared != null)
                    InputChip(
                      label: Text(
                        _shared! ? 'Condiviso C' : 'Personale',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onDeleted: () => setState(() => _shared = null),
                    ),
                ],
              ),
            ),
          if (usesPhoneLayout(context)) ...[
            for (final t in visible)
              Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: Icon(
                    expenseCategoryStyle(t.description).$1,
                    color: expenseCategoryStyle(t.description).$2,
                  ),
                  title: Text(
                    t.description,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${_dateLabel(t)} · ${t.shared ? 'Condiviso C' : 'Personale'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    t.amount == null ? '—' : amount(-t.amount!),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.amount == null
                          ? expenseMuted
                          : t.amount! < 0
                          ? AppColors.green
                          : const Color(0xFFED5C62),
                    ),
                  ),
                  onTap: () => _details(t),
                ),
              ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Nessuna transazione corrispondente.'),
              ),
          ] else
            LayoutBuilder(
              builder: (context, box) => Scrollbar(
                controller: _horizontal,
                thumbVisibility: box.maxWidth < 820,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(820, box.maxWidth),
                    child: Column(
                      children: [
                        Container(
                          height: 29,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F7),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            children: [
                              _cell(
                                'Data',
                                2,
                                heading: true,
                                onTap: () => _sort(false),
                              ),
                              _cell('Descrizione', 6, heading: true),
                              _cell('Categoria', 4, heading: true),
                              _cell('Conto', 4, heading: true),
                              _cell(
                                'Importo',
                                3,
                                heading: true,
                                numeric: true,
                                onTap: () => _sort(true),
                              ),
                            ],
                          ),
                        ),
                        for (final t in visible)
                          InkWell(
                            onTap: () => _details(t),
                            child: Container(
                              height: 37,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: AppColors.border),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _cell(_dateLabel(t), 2),
                                  _cell(
                                    t.description,
                                    6,
                                    icon: expenseCategoryStyle(
                                      t.description,
                                    ).$1,
                                  ),
                                  _cell(
                                    t.description,
                                    4,
                                    icon: expenseCategoryStyle(
                                      t.description,
                                    ).$1,
                                    iconColor: expenseCategoryStyle(
                                      t.description,
                                    ).$2,
                                  ),
                                  _cell(
                                    t.shared ? 'Condiviso C' : 'Personale',
                                    4,
                                  ),
                                  _cell(
                                    t.amount == null ? '—' : amount(-t.amount!),
                                    3,
                                    numeric: true,
                                    color: t.amount == null
                                        ? expenseMuted
                                        : t.amount! < 0
                                        ? AppColors.green
                                        : const Color(0xFFED5C62),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (rows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('Nessuna transazione corrispondente.'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${rows.length} operazioni · ${_allHistory ? 'Storico completo' : expenseLongMonth(widget.month)}',
                  style: const TextStyle(fontSize: 11, color: expenseMuted),
                ),
              ),
              IconButton(
                tooltip: 'Pagina precedente',
                onPressed: page > 0
                    ? () => setState(() => _page = page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left, size: 18),
              ),
              Text(
                '${page + 1} / $pages',
                style: const TextStyle(fontSize: 11, color: expenseMuted),
              ),
              IconButton(
                tooltip: 'Pagina successiva',
                onPressed: page < pages - 1
                    ? () => setState(() => _page = page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _sort(bool byAmount) => setState(() {
    _ascending = _sortAmount == byAmount ? !_ascending : false;
    _sortAmount = byAmount;
    _page = 0;
  });
  Widget _cell(
    String text,
    int flex, {
    bool heading = false,
    bool numeric = false,
    IconData? icon,
    Color? iconColor,
    Color? color,
    VoidCallback? onTap,
  }) => Expanded(
    flex: flex,
    child: InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: numeric
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor ?? expenseMuted),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: heading ? FontWeight.w600 : FontWeight.w400,
                color: color ?? expenseMuted,
              ),
            ),
          ),
          if (onTap != null)
            Icon(
              (_sortAmount == numeric && _ascending)
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 11,
              color: expenseMuted,
            ),
        ],
      ),
    ),
  );
}
