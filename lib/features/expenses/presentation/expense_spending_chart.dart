import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../markets/presentation/finance_widgets.dart';
import '../domain/expense_summary.dart';
import 'expense_dashboard_widgets.dart';

/// A full-month axis with an actual-only series and an independently drawn cap.
class ExpenseSpendingChart extends StatefulWidget {
  const ExpenseSpendingChart({
    required this.summary,
    required this.limit,
    super.key,
  });
  final ExpenseMonthSummary summary;
  final double limit;
  @override
  State<ExpenseSpendingChart> createState() => _ExpenseSpendingChartState();
}

class _ExpenseSpendingChartState extends State<ExpenseSpendingChart> {
  double? _pointer;
  @override
  void didUpdateWidget(covariant ExpenseSpendingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.month != widget.summary.month) _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.summary.cumulative;
    if (points.isEmpty) {
      return Center(
        child: Text(
          widget.summary.undated.isNotEmpty
              ? 'Le spese senza data sono incluse nel totale mensile. Per il grafico giornaliero occorrono le date.'
              : widget.summary.available
              ? 'Nessuna spesa registrata nel mese.'
              : 'Spese non disponibili per questo mese.',
          style: const TextStyle(fontSize: 12, color: expenseMuted),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        const left = 38.0, right = 9.0, top = 22.0, bottom = 27.0;
        final plot = Rect.fromLTRB(
          left,
          top,
          math.max(left + 1, box.maxWidth - right),
          math.max(top + 1, box.maxHeight - bottom),
        );
        final days = DateTime(
          widget.summary.month.year,
          widget.summary.month.month + 1,
          0,
        ).day;
        final values = points.map((p) => p.$2);
        final lo = math.min(0.0, values.reduce(math.min));
        final maxValue = math.max(widget.limit, values.reduce(math.max));
        final step = _niceStep(math.max(1, maxValue - lo) / 3);
        final hi = step * 3;
        final low = lo < 0 ? (lo / step).floor() * step : 0.0;
        final index = _pointer == null
            ? points.length - 1
            : (((_pointer! - plot.left) / plot.width * (days - 1)).round())
                  .clamp(0, points.length - 1);
        final selected = points[index];
        final selectedX =
            plot.left + (selected.$1.day - 1) / (days - 1) * plot.width;
        final selectedY =
            plot.bottom - (selected.$2 - low) / (hi - low) * plot.height;
        final tooltipX = (selectedX + 12)
            .clamp(plot.left, math.max(plot.left, box.maxWidth - 145))
            .toDouble();
        final tooltipY = (selectedY - 59)
            .clamp(0.0, math.max(0.0, box.maxHeight - 75))
            .toDouble();
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          onHover: (e) => setState(() => _pointer = e.localPosition.dx),
          onExit: (_) => setState(() => _pointer = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) => setState(() => _pointer = e.localPosition.dx),
            onHorizontalDragUpdate: (e) =>
                setState(() => _pointer = e.localPosition.dx),
            child: Semantics(
              label:
                  'Spese cumulate al ${dayLabel(selected.$1)}: ${amount(selected.$2)}. Budget: ${amount(widget.limit)}.',
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SpendingPainter(
                        points,
                        widget.limit,
                        days,
                        plot,
                        low,
                        hi,
                        index,
                        widget.summary.month,
                      ),
                    ),
                  ),
                  Positioned(
                    left: tooltipX,
                    top: tooltipY,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .97),
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0F12283B),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ${amount(selected.$2)}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${selected.$1.day} ${expenseLongMonth(selected.$1).toLowerCase()}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: expenseMuted,
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
          ),
        );
      },
    );
  }

  double _niceStep(double v) {
    final power = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final n = v / power;
    return (n <= 1
            ? 1
            : n <= 2
            ? 2
            : n <= 2.5
            ? 2.5
            : n <= 5
            ? 5
            : n <= 8
            ? 8
            : 10) *
        power;
  }
}

class _SpendingPainter extends CustomPainter {
  _SpendingPainter(
    this.points,
    this.limit,
    this.days,
    this.plot,
    this.low,
    this.high,
    this.selected,
    this.month,
  );
  final List<(DateTime, double)> points;
  final double limit, low, high;
  final int days, selected;
  final Rect plot;
  final DateTime month;
  Offset pos(int day, double v) => Offset(
    plot.left + (day - 1) / (days - 1) * plot.width,
    plot.bottom - (v - low) / (high - low) * plot.height,
  );
  void label(Canvas canvas, String text, Offset at, {bool right = false}) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 10,
          color: expenseMuted,
          fontFamily: 'Segoe UI Variable',
          fontFamilyFallback: ['Segoe UI', 'Arial', 'sans-serif'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, Offset(right ? at.dx - p.width : at.dx, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFEDEDF0)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = plot.bottom - plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      label(
        canvas,
        amount(low + (high - low) * i / 3, currency: '', digits: 0),
        Offset(plot.left - 9, y - 5),
        right: true,
      );
    }
    final ticks = <int>{1, 5, 10, 15, 20, 25, days};
    for (final day in ticks) {
      final x = pos(day, 0).dx;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      if (size.width > 500 || day == 1 || day == 15 || day == days) {
        final name = expenseLongMonth(month).substring(0, 3).toLowerCase();
        label(
          canvas,
          '$day $name',
          Offset(
            x -
                (day == 1
                    ? 0
                    : day == days
                    ? 28
                    : 12),
            plot.bottom + 12,
          ),
        );
      }
    }
    final budgetY = pos(1, limit).dy;
    for (var x = plot.left; x < plot.right; x += 10) {
      canvas.drawLine(
        Offset(x, budgetY),
        Offset(math.min(x + 6, plot.right), budgetY),
        Paint()
          ..color = expenseBlue
          ..strokeWidth = 1.5,
      );
    }
    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final p = pos(points[i].$1.day, points[i].$2);
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
      }
    }
    final area = Path.from(line)
      ..lineTo(pos(points.last.$1.day, 0).dx, plot.bottom)
      ..lineTo(pos(points.first.$1.day, 0).dx, plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x5532C691), Color(0x0A32C691)],
        ).createShader(plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.green
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    final active = pos(points[selected].$1.day, points[selected].$2);
    canvas.drawLine(
      Offset(active.dx, active.dy),
      Offset(active.dx, plot.bottom),
      Paint()..color = AppColors.green.withValues(alpha: .15),
    );
    canvas.drawCircle(active, 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(active, 4, Paint()..color = AppColors.green);
  }

  @override
  bool shouldRepaint(covariant _SpendingPainter old) =>
      old.points != points ||
      old.limit != limit ||
      old.selected != selected ||
      old.plot != plot;
}
