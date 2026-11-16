import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../markets/presentation/finance_widgets.dart';
import '../domain/expense_summary.dart';

const expenseBlue = Color(0xFF3199FF);
const expenseMuted = Color(0xFF70809E);

class ExpensePanel extends StatelessWidget {
  const ExpensePanel({required this.child, this.padding = 18, super.key});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x030B4938),
          blurRadius: 14,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          height: 1.25,
          fontFamily: 'Segoe UI Variable',
          fontFamilyFallback: ['Segoe UI', 'Arial', 'sans-serif'],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(
              context,
            ).textTheme.apply(fontFamily: 'Segoe UI Variable'),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 24),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class ExpenseHeading extends StatelessWidget {
  const ExpenseHeading(
    this.title,
    this.icon, {
    this.action,
    this.subtitle,
    super.key,
  });
  final String title;
  final IconData icon;
  final Widget? action;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: AppColors.green, size: 23),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(fontSize: 11, color: expenseMuted),
              ),
          ],
        ),
      ),
      ?action,
    ],
  );
}

class ExpenseMonthPicker extends StatelessWidget {
  const ExpenseMonthPicker({
    required this.month,
    required this.months,
    required this.onChanged,
    this.arrows = false,
    super.key,
  });
  final DateTime month;
  final List<String> months;
  final ValueChanged<DateTime> onChanged;
  final bool arrows;
  @override
  Widget build(BuildContext context) => Container(
    height: usesPhoneLayout(context)
        ? 48
        : arrows
        ? 42
        : 33,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (arrows &&
            MediaQuery.sizeOf(context).width >= 360 &&
            !usesPhoneLayout(context))
          const Padding(
            padding: EdgeInsets.only(left: 8, right: 10),
            child: Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: expenseMuted,
            ),
          ),
        if (arrows)
          IconButton(
            tooltip: 'Mese precedente',
            onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
            icon: const Icon(Icons.chevron_left, size: 18),
            constraints: const BoxConstraints.tightFor(width: 27, height: 32),
            padding: EdgeInsets.zero,
          ),
        DropdownButtonHideUnderline(
          child: SizedBox(
            width: usesPhoneLayout(context)
                ? math.min(160, MediaQuery.sizeOf(context).width - 210)
                : null,
            child: DropdownButton<String>(
              isExpanded: usesPhoneLayout(context),
              value: '${month.year}-${month.month.toString().padLeft(2, '0')}',
              isDense: true,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontFamily: 'Segoe UI Variable',
                fontFamilyFallback: ['Segoe UI', 'Arial', 'sans-serif'],
              ),
              icon: const Padding(
                padding: EdgeInsets.only(left: 15),
                child: Icon(Icons.expand_more, size: 17, color: expenseMuted),
              ),
              items: [
                for (final key in months)
                  DropdownMenuItem(
                    value: key,
                    child: Text(expenseLongMonth(DateTime.parse('$key-01'))),
                  ),
              ],
              onChanged: (key) {
                if (key != null) onChanged(DateTime.parse('$key-01'));
              },
            ),
          ),
        ),
        if (arrows)
          IconButton(
            tooltip: 'Mese successivo',
            onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
            icon: const Icon(Icons.chevron_right, size: 18),
            constraints: const BoxConstraints.tightFor(width: 30, height: 32),
            padding: EdgeInsets.zero,
          ),
      ],
    ),
  );
}

class ExpenseStat extends StatelessWidget {
  const ExpenseStat({
    required this.label,
    required this.value,
    required this.icon,
    this.footer,
    this.progress,
    this.onTap,
    super.key,
  });
  final String label;
  final double? value, progress;
  final IconData icon;
  final Widget? footer;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ExpensePanel(
    padding: 13,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 53,
            height: 53,
            decoration: BoxDecoration(
              color: const Color(0xFFE9FAF3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 26, color: AppColors.green),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: expenseMuted),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount(value),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                if (progress != null) ...[
                  ExpenseBar(progress!),
                  const SizedBox(height: 4),
                ],
                ?footer,
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ExpenseBar extends StatelessWidget {
  const ExpenseBar(this.value, {this.color = AppColors.green, super.key});
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1),
      color: color,
      backgroundColor: const Color(0xFFEDEDF0),
      minHeight: 7,
    ),
  );
}

class ExpenseDelta extends StatelessWidget {
  const ExpenseDelta(this.value, this.month, {required this.days, super.key});
  final double? value;
  final DateTime month;
  final int days;
  @override
  Widget build(BuildContext context) {
    final down = value != null && value! <= 0;
    final color = down ? AppColors.green : AppColors.danger;
    return Tooltip(
      message:
          'Confronto sui primi $days giorni disponibili di entrambi i mesi.',
      child: Row(
        children: [
          if (value != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    down ? Icons.south : Icons.north,
                    size: 12,
                    color: color,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${value! > 0 ? '+' : ''}${value!.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              value == null
                  ? 'Confronto non disponibile'
                  : 'rispetto a ${expenseLongMonth(DateTime(month.year, month.month - 1))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: expenseMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class ExpenseBudgetControl extends StatelessWidget {
  const ExpenseBudgetControl({
    required this.summary,
    required this.limit,
    required this.onEdit,
    super.key,
  });
  final ExpenseMonthSummary summary;
  final double limit;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final spent = summary.spent;
    final ratio = spent == null
        ? null
        : limit > 0
        ? spent / limit
        : spent > 0
        ? double.infinity
        : 0.0;
    final residue = spent == null ? null : limit - spent;
    final color = residue != null && residue < 0
        ? AppColors.danger
        : AppColors.green;
    final monthEnd = DateTime(summary.month.year, summary.month.month + 1, 0);
    final projection = summary.average == null
        ? null
        : summary.average! * monthEnd.day;
    final message = spent == null
        ? 'Collega la fonte per controllare il budget del mese.'
        : residue! < 0
        ? 'Budget superato di ${amount(-residue)}. Puoi rivedere il massimale nei dettagli.'
        : limit == 0
        ? 'Imposta un massimale per monitorare le spese del mese.'
        : summary.cutoff.isBefore(monthEnd) && projection != null
        ? 'Al ritmo attuale: ${amount(projection)} a fine mese, ${projection <= limit ? 'entro il budget.' : 'oltre il budget.'}'
        : 'Mese concluso con un residuo di ${amount(residue)}.';
    return ExpensePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpenseHeading(
            'Controllo budget',
            Icons.track_changes,
            action: TextButton(
              onPressed: onEdit,
              child: const Text(
                'Dettagli budget ›',
                style: TextStyle(fontSize: 11, color: expenseMuted),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: ratio == null ? 0 : ratio.clamp(0, 1),
                          strokeWidth: 11,
                          strokeCap: StrokeCap.round,
                          color: color,
                          backgroundColor: const Color(0xFFEBF1F1),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ratio == null || !ratio.isFinite
                                ? '—'
                                : '${(ratio * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const Text(
                            'Utilizzato',
                            style: TextStyle(fontSize: 11, color: expenseMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Budget mensile',
                        style: TextStyle(fontSize: 11, color: expenseMuted),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          amount(limit),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _line('Spese attuali', spent),
                      const Divider(height: 12),
                      _line('Residuo', residue, color: color),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FAF6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  color: AppColors.green,
                  size: 23,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 11,
                      color: expenseMuted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, double? value, {Color color = AppColors.text}) =>
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: expenseMuted),
            ),
          ),
          Text(
            amount(value),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      );
}

(IconData, Color) expenseCategoryStyle(String name) {
  final n = name.toLowerCase();
  if (n.contains('casa')) return (Icons.home_outlined, const Color(0xFFEE8109));
  if (n.contains('spesa') || n.contains('amazon')) {
    return (Icons.shopping_bag_outlined, const Color(0xFFE77B11));
  }
  if (n.contains('ristorante')) {
    return (Icons.restaurant_outlined, const Color(0xFF9A4DED));
  }
  if (n.contains('viaggi')) {
    return (Icons.flight_outlined, const Color(0xFF9A4DED));
  }
  if (n.contains('vestiti')) return (Icons.checkroom_outlined, expenseBlue);
  if (n.contains('trasport') ||
      n.contains('auto') ||
      n.contains('carburante')) {
    return (Icons.directions_car_outlined, expenseBlue);
  }
  if (n.contains('abbonamenti')) {
    return (Icons.credit_card, const Color(0xFF9A4DED));
  }
  if (n.contains('svago')) {
    return (Icons.sports_esports_outlined, const Color(0xFF9A4DED));
  }
  if (n.contains('regali')) return (Icons.redeem_outlined, AppColors.green);
  if (n.contains('parrucch')) {
    return (Icons.content_cut, const Color(0xFFEA5C9D));
  }
  if (n.contains('dottore') ||
      n.contains('farmacia') ||
      n.contains('dermato')) {
    return (Icons.health_and_safety_outlined, const Color(0xFFEA5C9D));
  }
  if (n.contains('bancarie')) {
    return (Icons.account_balance_outlined, expenseMuted);
  }
  if (n.contains('invest')) return (Icons.trending_up, AppColors.green);
  if (n.contains('palestra')) return (Icons.fitness_center, expenseBlue);
  return (Icons.more_horiz, expenseMuted);
}

class ExpenseCategories extends StatelessWidget {
  const ExpenseCategories({
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.monthPicker,
    required this.onCategory,
    super.key,
  });
  final ExpenseMonthSummary summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget monthPicker;
  final ValueChanged<String> onCategory;
  @override
  Widget build(BuildContext context) => ExpensePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpenseHeading(
          'Spese per categoria',
          Icons.pie_chart_outline,
          action: LayoutBuilder(
            builder: (context, box) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (MediaQuery.sizeOf(context).width > 1050) monthPicker,
                TextButton(
                  onPressed: onToggle,
                  child: Text(
                    expanded ? 'Riduci ‹' : 'Vedi tutte ›',
                    style: const TextStyle(fontSize: 11, color: expenseMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (summary.categories.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Categorie non disponibili.'),
          ),
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 760
                ? 5
                : box.maxWidth >= 550
                ? 4
                : box.maxWidth >= 380
                ? 3
                : 2;
            final visible = expanded
                ? summary.categories
                : summary.categories.take(cols * 2);
            return Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                for (final e in visible)
                  SizedBox(
                    width: (box.maxWidth - (cols - 1) * 18) / cols,
                    child: _category(e),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
  Widget _category(MapEntry<String, double?> e) {
    final (icon, color) = expenseCategoryStyle(e.key);
    final share = e.value == null || summary.spent == null || summary.spent == 0
        ? null
        : e.value! / summary.spent!;
    return InkWell(
      onTap: () => onCategory(e.key),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 62,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 41,
              height: 41,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.text),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      amount(e.value),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      share == null
                          ? '—'
                          : '${(share * 100).toStringAsFixed(1).replaceAll('.', ',')}%',
                      style: const TextStyle(fontSize: 9, color: expenseMuted),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ExpenseBar(
                    share ?? 0,
                    color: color == expenseBlue ? color : AppColors.green,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExpenseAccounts extends StatelessWidget {
  const ExpenseAccounts({
    required this.values,
    required this.expanded,
    required this.onToggle,
    super.key,
  });
  final Map<String, double?> values;
  final bool expanded;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => ExpensePanel(
    padding: 14,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpenseHeading(
          'Conti e fondi',
          Icons.account_balance_outlined,
          action: TextButton(
            onPressed: onToggle,
            child: Text(
              expanded ? 'Riduci ‹' : 'Vedi tutti ›',
              style: const TextStyle(fontSize: 11, color: expenseMuted),
            ),
          ),
        ),
        const SizedBox(height: 9),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final e
                  in expanded ? values.entries : values.entries.take(6))
                SizedBox(
                  width: (box.maxWidth - 10) / 2,
                  height: usesPhoneLayout(context)
                      ? 64 * MediaQuery.textScalerOf(context).scale(1)
                      : 47,
                  child: Tooltip(
                    message:
                        '${e.key}: ${amount(e.value)} · saldo dalla fonte Excel',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 29,
                            height: 29,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: e.key == 'Conto principale'
                                  ? const Color(0xFF222525)
                                  : e.key == 'Conto investimenti'
                                  ? const Color(0xFF0066B4)
                                  : const Color(0xFFF0F7F7),
                              borderRadius: BorderRadius.circular(
                                e.key == 'Conto principale' ||
                                        e.key == 'Sottoconto'
                                    ? 20
                                    : 7,
                              ),
                            ),
                            child: e.key.contains('Fondo')
                                ? const Icon(
                                    Icons.savings_outlined,
                                    size: 19,
                                    color: AppColors.green,
                                  )
                                : Text(
                                    e.key
                                        .split(' ')
                                        .last
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          e.key == 'Conto principale' ||
                                              e.key == 'Conto investimenti'
                                          ? Colors.white
                                          : expenseBlue,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  e.key,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: expenseMuted,
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    amount(e.value),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ExpensePair extends StatelessWidget {
  const ExpensePair({
    required this.left,
    required this.right,
    this.height,
    super.key,
  });
  final Widget left, right;
  final double? height;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth >= 1100
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: height == null
                    ? left
                    : SizedBox(height: height, child: left),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: height == null
                    ? right
                    : SizedBox(height: height, child: right),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              height == null ? left : SizedBox(height: height, child: left),
              const SizedBox(height: 12),
              height == null
                  ? right
                  : SizedBox(height: math.max(height!, 280), child: right),
            ],
          ),
  );
}
