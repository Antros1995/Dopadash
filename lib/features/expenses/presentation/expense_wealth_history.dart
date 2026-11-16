import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../investments/portfolio.dart';
import '../../investments/portfolio_history_card.dart';
import '../../markets/presentation/finance_widgets.dart';
import '../domain/expense_workbook.dart';
import 'expense_dashboard_widgets.dart';
import 'expense_year_table.dart';

class ExpenseWealthSeries {
  ExpenseWealthSeries(this.label, List<TimeValue> values)
    : points = List<TimeValue>.of(values)
        ..sort((a, b) => a.time.compareTo(b.time)) {
    latest = points.isEmpty ? null : points.last;
    minimum = points.isEmpty
        ? null
        : points.map((p) => p.value).reduce(math.min);
    maximum = points.isEmpty
        ? null
        : points.map((p) => p.value).reduce(math.max);
    double? before;
    if (latest != null) {
      for (final point in points) {
        if (point.time.year == latest!.time.year - 1 &&
            point.time.month == latest!.time.month) {
          before = point.value;
        }
      }
    }
    annualChange = before == null || before == 0
        ? null
        : (latest!.value - before) / before.abs() * 100;
  }
  final String label;
  final List<TimeValue> points;
  late final TimeValue? latest;
  late final double? minimum, maximum, annualChange;
}

class ExpenseWealthHistory extends StatelessWidget {
  const ExpenseWealthHistory({
    required this.data,
    required this.year,
    required this.portfolio,
    super.key,
  });
  final ExpenseData? data;
  final int year;
  final PortfolioController portfolio;
  static const _labels = [
    ['Patrimonio', 'totpatrimonio', 'totalepatrimonio'],
    ['Totale liquidi', 'totliquidi', 'liquidi'],
  ];
  ExpenseWealthSeries _series(List<String> aliases) {
    if (data != null) {
      for (final metric in data!.historyMetrics) {
        if (aliases.map(expenseLabel).contains(expenseLabel(metric))) {
          return ExpenseWealthSeries(aliases.first, [
            for (final p in data!.history(metric)) TimeValue(p.$1, p.$2),
          ]);
        }
      }
    }
    return ExpenseWealthSeries(aliases.first, const []);
  }

  @override
  Widget build(BuildContext context) => ExpensePanel(
    padding: 24,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFF0FAF6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.trending_up,
                size: 28,
                color: AppColors.green,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Andamento del patrimonio',
                    style: _style(
                      22,
                      weight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Patrimonio e liquidità dall’Excel · portafoglio dall’app',
                    style: _style(13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),
          _WealthBlock(series: _series(_labels[i])),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(height: 1),
        ),
        PortfolioHistoryCard(controller: portfolio),
        const SizedBox(height: 16),
        const Divider(height: 1),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 12),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(
            Icons.description_outlined,
            size: 22,
            color: AppColors.textMuted,
          ),
          title: Text(
            'Dati storici di dettaglio - $year',
            style: _style(14, color: AppColors.text),
          ),
          children: [
            if (data == null ||
                !data!.tables.any((t) => t.wealth && t.year == year))
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Dati storici non disponibili per il $year.',
                  style: _style(12),
                ),
              ),
            for (final table
                in data?.tables.where((t) => t.wealth && t.year == year) ??
                    <ExpenseYearTable>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ExpenseYearTableView(
                  key: ValueKey(table.reference),
                  table: table,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

TextStyle _style(
  double size, {
  Color color = expenseMuted,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontSize: size,
  height: 1.25,
  fontWeight: weight,
  color: color,
  fontFamily: 'Segoe UI Variable',
  fontFamilyFallback: const ['Segoe UI', 'Arial', 'sans-serif'],
  fontFeatures: const [FontFeature.tabularFigures()],
);

class _WealthBlock extends StatelessWidget {
  const _WealthBlock({required this.series});
  final ExpenseWealthSeries series;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, box) {
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                series.label,
                style: _style(
                  20,
                  weight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                series.latest == null
                    ? 'Dati mensili non disponibili.'
                    : '${dayLabel(series.latest!.time)} · ${series.label}: ${amount(series.latest!.value)}',
                style: _style(14, color: AppColors.green),
              ),
            ],
          );
          if (box.maxWidth >= 1100) {
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 24),
                SizedBox(
                  width: math.min(810, box.maxWidth * .57),
                  child: _kpis(),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 14), _kpis()],
          );
        },
      ),
      const SizedBox(height: 12),
      RepaintBoundary(child: ExpenseWealthChart(series: series)),
    ],
  );
  Widget _kpis() => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 610
          ? 4
          : box.maxWidth >= 290
          ? 2
          : 1;
      final width = (box.maxWidth - 10 * (columns - 1)) / columns;
      final delta = series.annualChange;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _kpi(
            context,
            width,
            'Valore attuale',
            amount(series.latest?.value),
            Icons.toll_outlined,
            tooltip:
                'Ultimo dato mensile disponibile nell’Excel, con la data indicata a sinistra.',
          ),
          _kpi(
            context,
            width,
            'Variazione (1 anno)',
            delta == null
                ? '—'
                : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1).replaceAll('.', ',')}%',
            delta != null && delta < 0 ? Icons.south_east : Icons.north_east,
            valueColor: delta == null
                ? AppColors.textMuted
                : delta < 0
                ? const Color(0xFFD33738)
                : AppColors.green,
            iconColor: delta != null && delta < 0
                ? const Color(0xFFD33738)
                : AppColors.green,
            tooltip:
                'Confronto con lo stesso mese dell’anno precedente. Non disponibile se manca il mese corrispondente o il valore iniziale è zero.',
          ),
          _kpi(
            context,
            width,
            'Massimo',
            amount(series.maximum),
            Icons.bar_chart,
            tooltip: 'Massimo dell’intera serie mensile disponibile.',
          ),
          _kpi(
            context,
            width,
            'Minimo',
            amount(series.minimum),
            Icons.south_east,
            iconColor: const Color(0xFFD33738),
            tooltip:
                'Minimo dell’intera serie mensile disponibile; include gli zeri registrati dalla fonte.',
          ),
        ],
      );
    },
  );
  Widget _kpi(
    BuildContext context,
    double width,
    String title,
    String value,
    IconData icon, {
    Color valueColor = AppColors.text,
    Color iconColor = AppColors.green,
    required String tooltip,
  }) => Tooltip(
    message: tooltip,
    child: Container(
      width: width,
      height: usesPhoneLayout(context)
          ? 64 * MediaQuery.textScalerOf(context).scale(1)
          : 58,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFD),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor == AppColors.green
                  ? const Color(0xFFEDF9F3)
                  : const Color(0xFFFFF2F2),
            ),
            child: Icon(icon, size: 19, color: iconColor),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(11),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: _style(
                      15,
                      weight: FontWeight.w600,
                      color: valueColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ExpenseWealthChart extends StatefulWidget {
  const ExpenseWealthChart({required this.series, super.key});
  final ExpenseWealthSeries series;
  @override
  State<ExpenseWealthChart> createState() => _ExpenseWealthChartState();
}

class _ExpenseWealthChartState extends State<ExpenseWealthChart> {
  int? _selected;
  @override
  void didUpdateWidget(covariant ExpenseWealthChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series != widget.series) _selected = null;
  }

  void _select(double x, Rect plot) {
    final points = widget.series.points;
    final target =
        points.first.time.millisecondsSinceEpoch +
        ((x - plot.left) / plot.width).clamp(0, 1) *
            (points.last.time.millisecondsSinceEpoch -
                points.first.time.millisecondsSinceEpoch);
    var best = 0;
    for (var i = 1; i < points.length; i++) {
      if ((points[i].time.millisecondsSinceEpoch - target).abs() <
          (points[best].time.millisecondsSinceEpoch - target).abs()) {
        best = i;
      }
    }
    if (best != _selected) setState(() => _selected = best);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series, points = series.points;
    if (points.isEmpty) {
      return SizedBox(
        height: 144,
        child: Center(
          child: Text(
            'Serie storica non disponibile per questo intervallo.',
            style: _style(12),
          ),
        ),
      );
    }
    return SizedBox(
      height: 144,
      child: LayoutBuilder(
        builder: (context, box) {
          final plot = Rect.fromLTRB(0, 8, math.max(1, box.maxWidth - 62), 118);
          final span = series.maximum! - series.minimum!;
          final margin = math.max(
            1.0,
            math.max(span * .12, series.maximum!.abs() * .02),
          );
          final low = series.minimum! - margin, high = series.maximum! + margin;
          final painter = _WealthPainter(series, plot, low, high, _selected);
          final index = _selected;
          final selected = index == null ? null : points[index];
          final location = selected == null ? null : painter.position(selected);
          return MouseRegion(
            onHover: (event) => _select(event.localPosition.dx, plot),
            onExit: (_) {
              if (_selected != null) setState(() => _selected = null);
            },
            cursor: SystemMouseCursors.precise,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (event) => _select(event.localPosition.dx, plot),
              onHorizontalDragUpdate: (event) =>
                  _select(event.localPosition.dx, plot),
              child: Semantics(
                label:
                    '${series.label}: ${amount((selected ?? series.latest!).value)} al ${dayLabel((selected ?? series.latest!).time)}.',
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: painter)),
                    if (selected != null && location != null)
                      Positioned(
                        left: (location.dx - 80)
                            .clamp(0.0, math.max(0.0, box.maxWidth - 175))
                            .toDouble(),
                        top: (location.dy - 54).clamp(0.0, 66.0).toDouble(),
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0D123B2D),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  amount(selected.value),
                                  style: _style(
                                    12,
                                    color: AppColors.text,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dayLabel(selected.time),
                                  style: _style(10),
                                ),
                              ],
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
    );
  }
}

class _WealthPainter extends CustomPainter {
  _WealthPainter(this.series, this.plot, this.low, this.high, this.selected);
  final ExpenseWealthSeries series;
  final Rect plot;
  final double low, high;
  final int? selected;
  Offset position(TimeValue point) {
    final first = series.points.first.time.millisecondsSinceEpoch,
        last = series.points.last.time.millisecondsSinceEpoch;
    return Offset(
      first == last
          ? plot.right
          : plot.left +
                (point.time.millisecondsSinceEpoch - first) /
                    (last - first) *
                    plot.width,
      plot.bottom - (point.value - low) / (high - low) * plot.height,
    );
  }

  void _label(
    Canvas canvas,
    String value,
    Offset position, {
    bool right = false,
  }) {
    final text = TextPainter(
      text: TextSpan(text: value, style: _style(11)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 60);
    text.paint(
      canvas,
      Offset(right ? position.dx - text.width : position.dx, position.dy),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE3E3E8)
      ..strokeWidth = .8;
    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      for (var x = plot.left; x < plot.right; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, plot.right), y),
          grid,
        );
      }
      _label(
        canvas,
        amount(high - (high - low) * i / 4, currency: '', digits: 0),
        Offset(plot.right + 10, y - 6),
      );
    }
    canvas.drawLine(
      plot.topRight,
      plot.bottomRight,
      Paint()..color = const Color(0xFFD9D9DE),
    );
    canvas.drawLine(
      plot.bottomLeft,
      plot.bottomRight,
      Paint()..color = const Color(0xFFD9D9DE),
    );
    final segments = <List<TimeValue>>[];
    for (final point in series.points) {
      if (segments.isEmpty ||
          (point.time.year * 12 + point.time.month) -
                  (segments.last.last.time.year * 12 +
                      segments.last.last.time.month) >
              1) {
        segments.add([]);
      }
      segments.last.add(point);
    }
    for (final points in segments) {
      final line = Path();
      for (var i = 0; i < points.length; i++) {
        final at = position(points[i]);
        if (i == 0) {
          line.moveTo(at.dx, at.dy);
        } else {
          line.lineTo(at.dx, at.dy);
        }
      }
      final area = Path.from(line)
        ..lineTo(position(points.last).dx, plot.bottom)
        ..lineTo(position(points.first).dx, plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x4432BD8B), Color(0x0632BD8B)],
          ).createShader(plot),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.green
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      if (points.length == 1) {
        canvas.drawCircle(
          position(points.single),
          2.5,
          Paint()..color = AppColors.green,
        );
      }
    }
    final last = position(series.points.last);
    canvas.drawCircle(last, 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(last, 4.5, Paint()..color = AppColors.green);
    if (selected != null) {
      final at = position(series.points[selected!]);
      canvas.drawLine(
        Offset(at.dx, plot.top),
        Offset(at.dx, plot.bottom),
        Paint()..color = AppColors.green.withValues(alpha: .2),
      );
      canvas.drawCircle(at, 5, Paint()..color = Colors.white);
      canvas.drawCircle(at, 3.5, Paint()..color = AppColors.green);
    }
    _label(
      canvas,
      dayLabel(series.points.first.time),
      Offset(plot.left, plot.bottom + 11),
    );
    if (series.points.length > 1) {
      _label(
        canvas,
        dayLabel(series.points.last.time),
        Offset(plot.right, plot.bottom + 11),
        right: true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WealthPainter old) =>
      old.series != series || old.plot != plot || old.selected != selected;
}
