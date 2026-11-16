import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../domain/body_statistics.dart';

const sleepColor = Color(0xFF8651FF);
const heartColor = Color(0xFFFF7167);
const hrvColor = Color(0xFF00C4E6);
const stageColors = [
  Color(0xFF4742A5),
  Color(0xFF4A9BFF),
  Color(0xFFA64CF4),
  Color(0xFFF17CDA),
];
Color metricColor(BodyMetric metric) => switch (metric) {
  BodyMetric.sleep || BodyMetric.efficiency => sleepColor,
  BodyMetric.restingHr => heartColor,
  BodyMetric.hrv => hrvColor,
  _ => AppColors.green,
};
IconData metricIcon(BodyMetric metric) => switch (metric) {
  BodyMetric.sleep => Icons.bedtime_outlined,
  BodyMetric.efficiency => Icons.bar_chart,
  BodyMetric.restingHr => Icons.favorite_border,
  BodyMetric.hrv => Icons.monitor_heart_outlined,
  BodyMetric.steps || BodyMetric.distance => Icons.directions_walk,
  BodyMetric.active => Icons.directions_run,
  _ => Icons.self_improvement,
};
String shortStatsDate(DateTime d) {
  const months = [
    'gen',
    'feb',
    'mar',
    'apr',
    'mag',
    'giu',
    'lug',
    'ago',
    'set',
    'ott',
    'nov',
    'dic',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

String rangeLabel(BodyRange r) =>
    '${shortStatsDate(r.start)} – ${shortStatsDate(r.end)} ${r.end.year}';

class StatsPanel extends StatelessWidget {
  const StatsPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.tint,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  @override
  Widget build(BuildContext context) => Material(
    color: tint ?? Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.border),
    ),
    child: Padding(
      padding: usesPhoneLayout(context) && padding == const EdgeInsets.all(18)
          ? const EdgeInsets.all(12)
          : padding,
      child: child,
    ),
  );
}

class StatsGrid extends StatelessWidget {
  const StatsGrid({
    required this.children,
    this.columns = 2,
    this.minWidth = 360,
    super.key,
  });
  final List<Widget> children;
  final int columns;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count =
          usesPhoneLayout(context) && columns == 4 && box.maxWidth >= 300
          ? 2
          : math.min(
              columns,
              math.max(1, ((box.maxWidth + 12) / (minWidth + 12)).floor()),
            );
      final width = (box.maxWidth - (count - 1) * 12) / count;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({required this.items, super.key});
  final List<(String, Color)> items;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 20,
    runSpacing: 8,
    children: [
      for (final item in items)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: item.$2,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item.$1,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
    ],
  );
}

class BodyChart extends StatefulWidget {
  const BodyChart({
    required this.values,
    required this.labels,
    required this.metric,
    this.previous,
    this.average = false,
    this.bars = false,
    this.stacks,
    this.boundary,
    this.beforeMean,
    this.duringMean,
    this.height = 205,
    this.xFractions,
    this.seriesLabel,
    this.pointDetails,
    super.key,
  });
  final List<double?> values;
  final List<String> labels;
  final BodyMetric metric;
  final List<double?>? previous;
  final bool average, bars;
  final List<List<double>?>? stacks;
  final int? boundary;
  final double? beforeMean, duringMean;
  final double height;
  final List<double>? xFractions;
  final String? seriesLabel;
  final List<String>? pointDetails;
  @override
  State<BodyChart> createState() => _BodyChartState();
}

class _BodyChartState extends State<BodyChart> {
  int? _hover;
  @override
  Widget build(BuildContext context) {
    final phone = usesPhoneLayout(context);
    final hasData =
        widget.values.any((v) => v != null) ||
        (widget.previous?.any((v) => v != null) ?? false);
    if (!hasData) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_chart_outlined,
                color: AppColors.textFaint,
                size: 30,
              ),
              SizedBox(height: 10),
              Text(
                'Nessun dato disponibile nel periodo',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    final hover = _hover != null && _hover! < widget.values.length
        ? _hover
        : null;
    return Semantics(
      label:
          '${widget.seriesLabel ?? widget.metric.label}: ${widget.values.whereType<double>().length} osservazioni. Seleziona un punto per il valore.',
      child: LayoutBuilder(
        builder: (context, box) {
          void select(Offset position) {
            var index =
                ((position.dx - 42) /
                        math.max(1, box.maxWidth - 54) *
                        widget.values.length)
                    .floor()
                    .clamp(0, widget.values.length - 1);
            if (widget.xFractions != null) {
              final fraction =
                  (position.dx - 42) / math.max(1, box.maxWidth - 54);
              var nearest = double.infinity;
              for (var i = 0; i < widget.xFractions!.length; i++) {
                final distance = (widget.xFractions![i] - fraction).abs();
                if (distance < nearest) {
                  nearest = distance;
                  index = i;
                }
              }
            }
            setState(() => _hover = index);
          }

          final plot = MouseRegion(
            onHover: (e) => select(e.localPosition),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              onTapDown: phone ? null : (e) => select(e.localPosition),
              onTapUp: phone ? (e) => select(e.localPosition) : null,
              child: Stack(
                children: [
                  SizedBox(
                    height: widget.height,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _ChartPainter(widget, hover, phone: phone),
                    ),
                  ),
                  if (hover != null && !phone)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: math.max(80, box.maxWidth - 10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F4),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${widget.labels[hover]} · ${widget.metric.format(widget.values[hover])}${widget.pointDetails == null ? '' : '\n${widget.pointDetails![hover]}'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
          if (!phone) return plot;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              plot,
              Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  hover == null
                      ? 'Tocca un punto per leggere i valori'
                      : '${widget.labels[hover]} · ${widget.metric.format(widget.values[hover])}${widget.pointDetails == null ? '' : '\n${widget.pointDetails![hover]}'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.chart, this.hover, {this.phone = false});
  final BodyChart chart;
  final int? hover;
  final bool phone;
  void label(
    Canvas canvas,
    String text,
    Offset at, {
    Color color = AppColors.textMuted,
    double size = 10,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: phone && size == 10 ? 11 : size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(42, 24, size.width - 12, size.height - 30);
    final all = [
      ...chart.values,
      ...?chart.previous,
    ].whereType<double>().toList();
    if (chart.stacks != null) {
      all.addAll(
        chart.stacks!.whereType<List<double>>().map(
          (v) => v.fold(0.0, (a, b) => a + b),
        ),
      );
    }
    if (all.isEmpty || rect.width <= 0) return;
    final high = all.reduce(math.max);
    final low = all.reduce(math.min);
    final baselineZero = chart.bars || chart.stacks != null;
    final minY = chart.metric.perception
        ? (chart.bars ? 0.0 : 1.0)
        : baselineZero
        ? 0.0
        : math.max(0.0, low - math.max(3, (high - low) * .25));
    final maxY = chart.metric.perception
        ? 5.0
        : math.max(minY + 1, high + math.max(1, (high - minY) * .18));
    final n = chart.values.length;
    double x(int i) =>
        rect.left + rect.width * (chart.xFractions?[i] ?? (i + .5) / n);
    double y(double v) =>
        rect.bottom - (v - minY) / (maxY - minY) * rect.height;
    if (chart.boundary != null) {
      final boundaryX = rect.left + rect.width * chart.boundary! / n;
      canvas.drawRect(
        Rect.fromLTRB(boundaryX, rect.top, rect.right, rect.bottom),
        Paint()..color = AppColors.greenSoft.withValues(alpha: .6),
      );
      canvas.drawRect(
        Rect.fromLTRB(rect.left, rect.top, boundaryX, rect.bottom),
        Paint()..color = const Color(0xFFF5F5F7),
      );
      canvas.drawLine(
        Offset(boundaryX, rect.top),
        Offset(boundaryX, rect.bottom),
        Paint()
          ..color = AppColors.textMuted
          ..strokeWidth = 1,
      );
      label(
        canvas,
        'Inizio pratica',
        Offset((boundaryX - 28).clamp(rect.left, rect.right - 70), 5),
        color: AppColors.text,
      );
      for (final entry in [
        (chart.beforeMean, rect.left, boundaryX),
        (chart.duringMean, boundaryX, rect.right),
      ]) {
        if (entry.$1 == null) continue;
        _dashed(
          canvas,
          Offset(entry.$2, y(entry.$1!)),
          Offset(entry.$3, y(entry.$1!)),
          AppColors.green,
        );
      }
    }
    final ticks = chart.metric.perception && chart.bars ? 5 : 4;
    for (var i = 0; i <= ticks; i++) {
      final v = minY + (maxY - minY) * i / ticks;
      final yy = y(v);
      canvas.drawLine(
        Offset(rect.left, yy),
        Offset(rect.right, yy),
        Paint()..color = AppColors.border,
      );
      final text = chart.metric == BodyMetric.sleep
          ? '${(v / 60).toStringAsFixed(0)} h'
          : v.toStringAsFixed(chart.metric == BodyMetric.distance ? 1 : 0);
      label(canvas, text, Offset(0, yy - 7));
    }
    final step = math.max(
      1,
      (n / math.max(2, rect.width / (phone ? 110 : 80))).ceil(),
    );
    for (var i = 0; i < n; i++) {
      if (i % step == 0 || (i == n - 1 && (!phone || i % step >= step / 2))) {
        label(
          canvas,
          chart.labels[i],
          Offset(
            (x(i) - 15).clamp(rect.left - 10, rect.right - 28),
            rect.bottom + 10,
          ),
        );
        canvas.drawLine(
          Offset(x(i), rect.top),
          Offset(x(i), rect.bottom),
          Paint()..color = AppColors.border.withValues(alpha: .6),
        );
      }
    }
    final color = metricColor(chart.metric);
    if (chart.stacks != null) {
      for (var i = 0; i < n; i++) {
        final stack = chart.stacks![i];
        if (stack == null) continue;
        var sum = 0.0;
        for (var j = 0; j < stack.length; j++) {
          final top = sum + stack[j];
          canvas.drawRect(
            Rect.fromLTRB(
              x(i) - rect.width / n * .32,
              y(top),
              x(i) + rect.width / n * .32,
              y(sum),
            ),
            Paint()..color = stageColors[j],
          );
          sum = top;
        }
      }
    } else if (chart.bars) {
      for (var i = 0; i < n; i++) {
        final v = chart.values[i];
        if (v != null) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(
                x(i) - rect.width / n * .32,
                y(v),
                x(i) + rect.width / n * .32,
                rect.bottom,
              ),
              const Radius.circular(3),
            ),
            Paint()..color = color.withValues(alpha: .48),
          );
        }
      }
    }
    void line(
      List<double?> values,
      Color color, {
      bool dashed = false,
      bool dots = false,
      double width = 1.8,
    }) {
      Offset? last;
      for (var i = 0; i < math.min(n, values.length); i++) {
        final value = values[i];
        if (value == null) {
          last = null;
          continue;
        }
        final point = Offset(x(i), y(value));
        if (last != null) {
          if (dashed) {
            _dashed(canvas, last, point, color);
          } else {
            canvas.drawLine(
              last,
              point,
              Paint()
                ..color = color
                ..strokeWidth = width,
            );
          }
        }
        final isolated =
            (i == 0 || values[i - 1] == null) &&
            (i + 1 >= math.min(n, values.length) || values[i + 1] == null);
        if (dots || n == 1 || isolated) {
          canvas.drawCircle(point, 3, Paint()..color = color);
        }
        last = point;
      }
    }

    if (chart.previous != null) {
      line(chart.previous!, AppColors.textFaint, dashed: true);
    }
    if (!chart.bars && chart.stacks == null) {
      line(chart.values, color, dots: n < 50);
    }
    if (chart.average) {
      line(
        movingAverage(chart.values),
        // Sopra le barre una linea dello stesso colore non si vedrebbe.
        chart.metric.perception || chart.bars ? AppColors.text : color,
        width: 2.6,
      );
    }
    if (hover != null) {
      canvas.drawLine(
        Offset(x(hover!), rect.top),
        Offset(x(hover!), rect.bottom),
        Paint()..color = AppColors.textMuted.withValues(alpha: .4),
      );
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Color color) {
    final delta = b - a, length = delta.distance;
    if (length == 0) return;
    for (var start = 0.0; start < length; start += 9) {
      c.drawLine(
        a + delta * (start / length),
        a + delta * (math.min(length, start + 5) / length),
        Paint()
          ..color = color
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) => true;
}

class SleepRegularity extends StatelessWidget {
  const SleepRegularity({required this.days, required this.range, super.key});
  final List<BodyDay> days;
  final BodyRange range;
  @override
  Widget build(BuildContext context) {
    final values = <(int, double, double)>[];
    for (final day in days.where((d) => range.contains(d.date))) {
      final details = day.sleepDetails;
      final start = DateTime.tryParse(details?['startTime'] as String? ?? '');
      final end = DateTime.tryParse(details?['endTime'] as String? ?? '');
      if (start == null || end == null) continue;
      final a = romeWallTime(start), b = romeWallTime(end);
      double hour(DateTime d) =>
          (d.hour < 18 ? d.hour + 24 : d.hour) + d.minute / 60;
      values.add((day.date.weekday, hour(a), hour(b)));
    }
    if (values.isEmpty) {
      return const SizedBox(
        height: 175,
        child: Center(child: Text('Orari del sonno non disponibili.')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 175,
          width: double.infinity,
          child: CustomPaint(painter: _RegularityPainter(values)),
        ),
        Text(
          '${values.length} notti con orari · Europe/Rome · medie per giorno di risveglio',
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _RegularityPainter extends CustomPainter {
  _RegularityPainter(this.values);
  final List<(int, double, double)> values;
  @override
  void paint(Canvas c, Size size) {
    void text(String value, Offset at) {
      (TextPainter(
        text: TextSpan(
          text: value,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout()).paint(c, at);
    }

    const names = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
    double x(double hour) => 40 + (hour - 18) / 24 * (size.width - 60);
    for (var i = 0; i < 7; i++) {
      final y = 12.0 + i * 21;
      text(names[i], Offset(0, y - 6));
      c.drawLine(
        Offset(40, y),
        Offset(size.width - 10, y),
        Paint()..color = AppColors.border,
      );
      final group = values.where((v) => v.$1 == i + 1).toList();
      if (group.isEmpty) continue;
      final a = group.fold(0.0, (s, v) => s + v.$2) / group.length;
      final b = group.fold(0.0, (s, v) => s + v.$3) / group.length;
      c.drawLine(
        Offset(x(a), y),
        Offset(x(b), y),
        Paint()
          ..color = sleepColor.withValues(alpha: .3)
          ..strokeWidth = 2,
      );
      c.drawCircle(Offset(x(a), y), 3.5, Paint()..color = stageColors.first);
      c.drawCircle(Offset(x(b), y), 3.5, Paint()..color = sleepColor);
    }
    for (var hour = 18; hour <= 42; hour += 4) {
      text(
        '${(hour % 24).toString().padLeft(2, '0')}:00',
        Offset(x(hour.toDouble()) - 10, 158),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RegularityPainter oldDelegate) => true;
}
