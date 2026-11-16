import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/modular_board.dart';
import '../../../core/presentation/app_card.dart';
import '../domain/market_models.dart';

String amount(double? value, {String currency = 'EUR', int digits = 2}) {
  if (value == null || !value.isFinite) return '—';
  final parts = value.abs().toStringAsFixed(digits).split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '${value < 0 ? '−' : ''}$grouped${digits > 0 ? ',${parts.last}' : ''}${currency.isEmpty ? '' : ' $currency'}';
}

String dayLabel(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

enum FinanceRange { day, week, month, quarter, year, all, custom }

extension RangeInfo on FinanceRange {
  String get label =>
      ['24H', '1W', '1M', '3M', '1Y', 'Tutto', 'Personalizzato'][index];
  MarketPeriod get query => switch (this) {
    FinanceRange.day => MarketPeriod.day,
    FinanceRange.week => MarketPeriod.week,
    FinanceRange.month => MarketPeriod.month,
    FinanceRange.quarter || FinanceRange.year => MarketPeriod.year,
    _ => MarketPeriod.max,
  };
  DateTime start(DateTime end) => switch (this) {
    FinanceRange.day => end.subtract(const Duration(days: 1)),
    FinanceRange.week => end.subtract(const Duration(days: 7)),
    FinanceRange.month => DateTime(end.year, end.month - 1, end.day),
    FinanceRange.quarter => DateTime(end.year, end.month - 3, end.day),
    FinanceRange.year => DateTime(end.year - 1, end.month, end.day),
    _ => DateTime(1970),
  };
}

class RangeSelector extends StatelessWidget {
  const RangeSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });
  final FinanceRange value;
  final ValueChanged<FinanceRange> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 5,
    children: [
      for (final range in FinanceRange.values)
        ChoiceChip(
          label: Text(range.label, style: const TextStyle(fontSize: 11)),
          selected: value == range,
          onSelected: (_) => onChanged(range),
          visualDensity: VisualDensity.compact,
        ),
    ],
  );
}

class FinanceCard extends StatelessWidget {
  const FinanceCard({
    required this.title,
    required this.child,
    this.action,
    super.key,
  });
  final String title;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => AppCard(
    // Keep finance cards aligned with the redesigned Spese panels.  The
    // content is still shared by Investimenti and Mercati, but the shell now
    // uses the same radius, border and soft shadow as the wealth history card.
    padding: const EdgeInsets.all(24),
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 14),
        Material(color: Colors.transparent, child: child),
      ],
    ),
  );
}

class TimeValue {
  const TimeValue(this.time, this.value);
  final DateTime time;
  final double value;
}

class FinanceChart extends StatefulWidget {
  const FinanceChart({
    required this.points,
    this.second = const [],
    this.label = 'Valore',
    this.secondLabel = 'Capitale',
    this.currency = 'EUR',
    this.height = 260,
    this.connectGaps = true,
    super.key,
  });
  final List<TimeValue> points, second;
  final String label, secondLabel, currency;
  final double height;
  final bool connectGaps;
  @override
  State<FinanceChart> createState() => _FinanceChartState();
}

class _FinanceChartState extends State<FinanceChart> {
  double? _hover;
  @override
  Widget build(BuildContext context) {
    final extent = BoardExtent.of(context);
    final chartHeight =
        (widget.height +
                (extent == null ? 0 : extent.height - extent.originalHeight))
            .clamp(160.0, 950.0);
    if (widget.points.isEmpty) {
      return SizedBox(
        height: chartHeight,
        child: const Center(
          child: Text(
            'Serie storica non disponibile per questo intervallo.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final points = widget.points;
        final f = ((_hover ?? box.maxWidth) / box.maxWidth).clamp(0.0, 1.0);
        final target =
            points.first.time.millisecondsSinceEpoch +
            (points.last.time.millisecondsSinceEpoch -
                    points.first.time.millisecondsSinceEpoch) *
                f;
        final point = points.reduce(
          (a, b) =>
              (a.time.millisecondsSinceEpoch - target).abs() <
                  (b.time.millisecondsSinceEpoch - target).abs()
              ? a
              : b,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${dayLabel(point.time)} · ${widget.label}: ${amount(point.value, currency: widget.currency)}',
              style: const TextStyle(fontSize: 12, color: AppColors.green),
            ),
            const SizedBox(height: 8),
            MouseRegion(
              onHover: (e) => setState(() => _hover = e.localPosition.dx),
              onExit: (_) => setState(() => _hover = null),
              child: SizedBox(
                height: chartHeight,
                child: CustomPaint(
                  painter: _FinancePainter(
                    points,
                    widget.second,
                    widget.connectGaps,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    dayLabel(points.first.time),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                Expanded(
                  child: Text(
                    dayLabel(points.last.time),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
            if (widget.second.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '● ${widget.label} (verde)     ● ${widget.secondLabel} (blu)',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FinancePainter extends CustomPainter {
  _FinancePainter(this.points, this.second, this.connectGaps);
  final List<TimeValue> points, second;
  final bool connectGaps;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 20) return;
    final values = [...points, ...second].map((p) => p.value);
    var min = values.reduce(math.min), max = values.reduce(math.max);
    final padding = math.max((max - min) * .12, max.abs() * .005 + .01);
    min -= padding;
    max += padding;
    final first = points.first.time.millisecondsSinceEpoch.toDouble(),
        last = points.last.time.millisecondsSinceEpoch.toDouble();
    Offset pos(TimeValue p) => Offset(
      (p.time.millisecondsSinceEpoch - first) /
          math.max(1, last - first) *
          (size.width - 64),
      size.height - 8 - (p.value - min) / (max - min) * (size.height - 16),
    );
    for (var i = 0; i <= 4; i++) {
      final y = 8 + (size.height - 16) * i / 4;
      final grid = Paint()
        ..color = const Color(0xFFE3E3E8)
        ..strokeWidth = .8;
      for (var x = 0.0; x < size.width - 64; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width - 64), y),
          grid,
        );
      }
      final text = TextPainter(
        text: TextSpan(
          text: amount(
            max - (max - min) * i / 4,
            currency: '',
            digits: max.abs() > 100 ? 0 : 2,
          ),
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 62);
      text.paint(canvas, Offset(size.width - 60, y - 5));
    }
    void line(List<TimeValue> data, Color color, {bool fill = false}) {
      if (data.isEmpty) return;
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final p = pos(data[i]);
        if (i == 0 ||
            (!connectGaps &&
                data[i].time.difference(data[i - 1].time).inDays > 1)) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      if (fill) {
        final area = Path.from(path)
          ..lineTo(pos(data.last).dx, size.height - 8)
          ..lineTo(pos(data.first).dx, size.height - 8)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader =
                const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x4432BD8B), Color(0x0632BD8B)],
                ).createShader(
                  Rect.fromLTWH(0, 8, size.width - 64, size.height - 16),
                ),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(pos(data.last), 4.5, Paint()..color = color);
    }

    line(second, const Color(0xFF4E8DDA));
    line(points, AppColors.green, fill: true);
  }

  @override
  bool shouldRepaint(covariant _FinancePainter old) => true;
}
