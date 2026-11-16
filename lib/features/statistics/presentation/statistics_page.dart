import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/presentation/app_card.dart';
import '../../../core/utils/date_formatters.dart';
import '../../routines/application/routine_controller.dart';
import '../../routines/domain/routine.dart';
import '../application/statistics_controller.dart';
import '../domain/routine_statistics.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({
    required this.routines,
    required this.controller,
    super.key,
  });

  final RoutineController routines;
  final StatisticsController controller;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.updateHistory(widget.routines.history);
    widget.controller.load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller;
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          thickness: 8,
          radius: const Radius.circular(8),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(32, 28, 44, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Statistiche',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'Scegli cosa osservare e confronta periodi omogenei.',
                ),
                const SizedBox(height: AppSpacing.lg),
                _Filters(controller: state),
                const SizedBox(height: AppSpacing.lg),
                if (state.isLoading)
                  const AppCard(
                    child: SizedBox(
                      height: 340,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (state.error != null)
                  _StatisticsError(onRetry: state.load)
                else if (state.current case final current?) ...[
                  _Metrics(current: current, previous: state.previous),
                  const SizedBox(height: AppSpacing.lg),
                  _TrendCard(
                    statistics: current,
                    period: state.period,
                    range: state.range,
                  ),
                ] else
                  const AppCard(
                    child: SizedBox(
                      height: 260,
                      child: Center(
                        child: Text('Nessuna routine da analizzare.'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: controller.routineId,
              decoration: const InputDecoration(
                labelText: 'Routine',
                prefixIcon: Icon(Icons.check_circle_outline_rounded),
              ),
              items: [
                for (final routine in controller.routineOptions)
                  DropdownMenuItem(
                    value: routine.id,
                    child: Text(routine.name),
                  ),
              ],
              onChanged: controller.setRoutine,
            ),
          ),
          SegmentedButton<StatisticsPeriod>(
            segments: [
              for (final period in StatisticsPeriod.values)
                ButtonSegment(value: period, label: Text(period.label)),
            ],
            selected: {controller.period},
            onSelectionChanged: (selection) async {
              final selected = selection.single;
              if (selected == StatisticsPeriod.custom) {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDateRange: controller.customRange == null
                      ? null
                      : DateTimeRange(
                          start: controller.customRange!.start,
                          end: controller.customRange!.endExclusive.subtract(
                            const Duration(days: 1),
                          ),
                        ),
                  locale: const Locale('it'),
                );
                if (range != null) await controller.setCustomRange(range);
              } else {
                await controller.setPeriod(selected);
              }
            },
          ),
          if (controller.period != StatisticsPeriod.custom)
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: controller.anchor,
                  locale: const Locale('it'),
                );
                if (date != null) await controller.setAnchor(date);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(formatShortDate(controller.anchor)),
            )
          else if (controller.customRange case final range?)
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDateRange: DateTimeRange(
                    start: range.start,
                    end: range.endExclusive.subtract(const Duration(days: 1)),
                  ),
                  locale: const Locale('it'),
                );
                if (selected != null) await controller.setCustomRange(selected);
              },
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: Text(
                '${formatShortDate(range.start)} – '
                '${formatShortDate(range.endExclusive.subtract(const Duration(days: 1)))}',
              ),
            ),
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.current, required this.previous});

  final RoutineStatistics current;
  final RoutineStatistics? previous;

  @override
  Widget build(BuildContext context) {
    final previousRate = previous?.completionRate;
    final difference = previousRate == null
        ? null
        : (current.completionRate - previousRate) * 100;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 4 : 2;
        const gap = AppSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: width,
              child: _MetricCard(
                label: 'Completamento',
                value: '${(current.completionRate * 100).round()}%',
                detail: difference == null
                    ? 'Nessun confronto'
                    : '${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(0)} pt sul periodo precedente',
                positive: difference == null || difference >= 0,
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricCard(
                label: 'Volte completata',
                value: '${current.completed}',
                detail: '${current.recorded} giorni registrati',
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricCard(
                label: 'Streak attuale',
                value: '${current.currentStreak}',
                detail: 'giorni consecutivi',
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricCard(
                label: 'Streak migliore',
                value: '${current.longestStreak}',
                detail: 'nel periodo selezionato',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    this.positive = true,
  });

  final String label;
  final String value;
  final String detail;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            detail,
            maxLines: 2,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: positive ? AppColors.textMuted : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.statistics,
    required this.period,
    required this.range,
  });

  final RoutineStatistics statistics;
  final StatisticsPeriod period;
  final StatisticsRange range;

  @override
  Widget build(BuildContext context) {
    final buckets = _buildBuckets(statistics.points, period);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: 'Andamento',
            subtitle:
                '${formatShortDate(range.start)} – '
                '${formatShortDate(range.endExclusive.subtract(const Duration(days: 1)))}',
          ),
          const SizedBox(height: AppSpacing.xl),
          if (statistics.eligibleDays == 0)
            const SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'Questa routine non era attiva nel periodo scelto.',
                ),
              ),
            )
          else
            SizedBox(height: 250, child: _BarChart(buckets: buckets)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Il calcolo considera solo i giorni in cui la routine era configurata. '
            'I dettagli specifici saranno aggiunti quando esiste una sorgente dati verificata.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _StatisticsError extends StatelessWidget {
  const _StatisticsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SizedBox(
        height: 280,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.query_stats_rounded,
              size: 40,
              color: AppColors.textFaint,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Non è stato possibile caricare le statistiche.'),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Riprova')),
          ],
        ),
      ),
    );
  }
}

class _TrendBucket {
  const _TrendBucket(this.label, this.rate, this.hasEligibleDays);

  final String label;
  final double rate;
  final bool hasEligibleDays;
}

List<_TrendBucket> _buildBuckets(
  List<RoutineDailyPoint> points,
  StatisticsPeriod period,
) {
  if (period != StatisticsPeriod.year && points.length <= 45) {
    return [
      for (final point in points)
        _TrendBucket(
          '${point.date.day}',
          point.status == RoutineStatus.ok ? 1 : 0,
          point.eligible,
        ),
    ];
  }
  final grouped = <String, List<RoutineDailyPoint>>{};
  for (final point in points) {
    final key = '${point.date.year}-${point.date.month}';
    grouped.putIfAbsent(key, () => []).add(point);
  }
  const monthLabels = <String>[
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
  return [
    for (final group in grouped.values)
      () {
        final eligible = group.where((point) => point.eligible).toList();
        final completed = eligible
            .where((point) => point.status == RoutineStatus.ok)
            .length;
        return _TrendBucket(
          monthLabels[group.first.date.month - 1],
          eligible.isEmpty ? 0 : completed / eligible.length,
          eligible.isNotEmpty,
        );
      }(),
  ];
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.buckets});

  final List<_TrendBucket> buckets;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(
          width: 38,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [Text('100%'), Text('50%'), Text('0%')],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    3,
                    (_) => const Divider(color: AppColors.border),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final bucket in buckets)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Tooltip(
                                message: bucket.hasEligibleDays
                                    ? '${(bucket.rate * 100).round()}%'
                                    : 'Non attiva',
                                child: Container(
                                  height: bucket.hasEligibleDays
                                      ? (constraints.maxHeight - 28) *
                                                bucket.rate +
                                            3
                                      : 3,
                                  decoration: BoxDecoration(
                                    color: bucket.hasEligibleDays
                                        ? AppColors.green
                                        : AppColors.border,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                bucket.label,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
