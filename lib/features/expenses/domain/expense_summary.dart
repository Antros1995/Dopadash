import 'dart:math' as math;
import 'expense_workbook.dart';

/// All monthly cards use the same adjusted ledger, cutoff and comparison window.
class ExpenseMonthSummary {
  ExpenseMonthSummary(ExpenseData? data, this.month, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final end = DateTime(month.year, month.month + 1, 0);
    cutoff = end.isBefore(today)
        ? end
        : DateTime(today.year, today.month, today.day);
    elapsedDays = cutoff.isBefore(month) ? 0 : math.min(cutoff.day, end.day);
    records = data?.month(month) ?? [];
    final endExclusive = DateTime(cutoff.year, cutoff.month, cutoff.day + 1);
    final actual = records.where((t) => t.date.isBefore(endExclusive)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    available =
        data != null &&
        data.availableMonths.contains(expenseMonthKey(month)) &&
        elapsedDays > 0 &&
        actual.every((t) => t.amount != null);
    spent = available ? actual.fold<double>(0, (s, t) => s + t.amount!) : null;
    undated = actual.where((t) => !t.hasExactDate).toList();
    undatedTotal = undated.any((t) => t.amount == null)
        ? null
        : undated.fold<double>(0, (sum, t) => sum + t.amount!);
    final dated = actual.where((t) => t.hasExactDate).toList();
    average = spent == null ? null : spent! / elapsedDays;
    final grouped = <String, double?>{};
    for (final table in data?.tables ?? <ExpenseYearTable>[]) {
      if (table.wealth || table.year != month.year) continue;
      for (final row in table.rows) {
        final name = expenseLabel(row.label);
        if (!name.startsWith('tot') && name != 'check') {
          grouped.putIfAbsent(row.label, () => available ? 0 : null);
        }
      }
    }
    final daily = <int, double>{};
    for (final t in actual) {
      if (!grouped.containsKey(t.description)) {
        grouped[t.description] = available ? 0 : null;
      }
      if (available) {
        grouped[t.description] = (grouped[t.description] ?? 0) + t.amount!;
        if (t.hasExactDate) {
          daily.update(
            t.date.day,
            (v) => v + t.amount!,
            ifAbsent: () => t.amount!,
          );
        }
      }
    }
    categories = grouped.entries.toList()
      ..sort((a, b) => (b.value ?? 0).compareTo(a.value ?? 0));
    // Stop at the last recorded expense; the budget alone spans the whole month.
    cumulative = [];
    if (available && dated.isNotEmpty) {
      var sum = 0.0;
      for (var day = 1; day <= dated.last.date.day; day++) {
        sum += daily[day] ?? 0;
        cumulative.add((DateTime(month.year, month.month, day), sum));
      }
    }
    final previous = DateTime(month.year, month.month - 1);
    final previousDays = math.min(
      elapsedDays,
      DateTime(month.year, month.month, 0).day,
    );
    final previousRecords =
        data
            ?.month(previous)
            .where((t) => t.date.day <= previousDays)
            .toList() ??
        [];
    if (available &&
        data!.availableMonths.contains(expenseMonthKey(previous)) &&
        previousDays > 0 &&
        undated.isEmpty &&
        previousRecords.every((t) => t.hasExactDate) &&
        previousRecords.every((t) => t.amount != null)) {
      final total = previousRecords.fold<double>(0, (s, t) => s + t.amount!);
      if (total != 0) change = (spent! - total) / total.abs() * 100;
      final previousAverage = total / previousDays;
      if (previousAverage != 0) {
        averageChange =
            (average! - previousAverage) / previousAverage.abs() * 100;
      }
    }
  }
  final DateTime month;
  late final DateTime cutoff;
  late final int elapsedDays;
  late final bool available;
  late final double? spent, average;
  late final double? undatedTotal;
  late final List<ExpenseTransaction> undated;
  double? change, averageChange;
  late final List<ExpenseTransaction> records;
  late final List<MapEntry<String, double?>> categories;
  late final List<(DateTime, double)> cumulative;
}

String expenseLongMonth(DateTime date) =>
    '${const ['Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno', 'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'][date.month - 1]} ${date.year}';
