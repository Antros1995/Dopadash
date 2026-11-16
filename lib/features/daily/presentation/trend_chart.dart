import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Andamento di una misura nel tempo (peso, vita, …).
///
/// Assi con numeri tondi, date leggibili, ultimo valore sempre scritto e,
/// passando il mouse o il dito, data e valore del punto più vicino.
class TrendChart extends StatefulWidget {
  const TrendChart({
    required this.points,
    required this.unit,
    this.color = AppColors.green,
    this.height = 190,
    super.key,
  });

  /// Punti in ordine di data.
  final List<(DateTime, double)> points;
  final String unit;
  final Color color;
  final double height;

  static String number(double v) => v
      .toStringAsFixed(1)
      .replaceAll(RegExp(r'\.0$'), '')
      .replaceAll('.', ',');

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _hover;

  void _point(Offset local, double width) {
    final points = widget.points;
    if (points.isEmpty) return;
    final geometry = _Geometry(points, Size(width, widget.height), widget.unit);
    var best = 0;
    var distance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = (geometry.at(points[i]).dx - local.dx).abs();
      if (d < distance) {
        distance = d;
        best = i;
      }
    }
    if (best != _hover) setState(() => _hover = best);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'Nessuna misura in questo periodo.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) => MouseRegion(
          onHover: (e) => _point(e.localPosition, box.maxWidth),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) => _point(e.localPosition, box.maxWidth),
            onHorizontalDragUpdate: (e) => _point(e.localPosition, box.maxWidth),
            child: CustomPaint(
              size: Size(box.maxWidth, widget.height),
              painter: _TrendPainter(
                widget.points,
                widget.unit,
                widget.color,
                _hover != null && _hover! < widget.points.length ? _hover : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _months = [
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

String _two(int n) => n.toString().padLeft(2, '0');
String _fullDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// Posizioni condivise tra disegno e ricerca del punto sotto il cursore.
class _Geometry {
  _Geometry(this.points, Size size, String unit) {
    final values = points.map((p) => p.$2);
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if (hi - lo < 1e-6) {
      lo -= 1;
      hi += 1;
    }
    // Passo "tondo": 0,5 · 1 · 2 · 5 · 10…
    final raw = (hi - lo) / 3;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final ratio = raw / magnitude;
    step = (ratio <= 1 ? 1 : ratio <= 2 ? 2 : ratio <= 5 ? 5 : 10) * magnitude;
    min = (lo / step).floor() * step;
    max = (hi / step).ceil() * step;
    if (max - min < step) max = min + step;
    final widest = [min, max]
        .map((v) => _measure(TrendChart.number(v)).width)
        .reduce(math.max);
    plot = Rect.fromLTRB(widest + 10, 22, size.width - 14, size.height - 24);
    first = points.first.$1;
    span = math.max(1, points.last.$1.difference(first).inHours).toDouble();
  }
  final List<(DateTime, double)> points;
  late final double step, min, max, span;
  late final Rect plot;
  late final DateTime first;

  Offset at((DateTime, double) p) => Offset(
    points.length == 1
        ? plot.center.dx
        : plot.left + plot.width * p.$1.difference(first).inHours / span,
    plot.bottom - plot.height * (p.$2 - min) / (max - min),
  );

  static TextPainter _measure(
    String text, {
    Color color = AppColors.textMuted,
    double size = 10.5,
    FontWeight weight = FontWeight.w400,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: size, color: color, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points, this.unit, this.color, this.hover);
  final List<(DateTime, double)> points;
  final String unit;
  final Color color;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(points, size, unit), plot = g.plot;
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;

    // Griglia orizzontale con valori tondi.
    for (var v = g.min; v <= g.max + g.step * .01; v += g.step) {
      final y = plot.bottom - plot.height * (v - g.min) / (g.max - g.min);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final label = _Geometry._measure(TrendChart.number(v));
      label.paint(canvas, Offset(plot.left - 8 - label.width, y - label.height / 2));
    }

    // Date: giorno/mese sui periodi brevi, mese e anno su quelli lunghi.
    final days = points.last.$1.difference(points.first.$1).inDays;
    final ticks = points.length == 1 ? 1 : math.min(5, math.max(2, plot.width ~/ 110));
    var lastRight = -double.infinity;
    for (var i = 0; i < ticks; i++) {
      final f = ticks == 1 ? .5 : i / (ticks - 1);
      final date = g.first.add(Duration(hours: (g.span * f).round()));
      final text = days <= 120
          ? '${_two(date.day)} ${_months[date.month - 1]}'
          : '${_months[date.month - 1]} ${_two(date.year % 100)}';
      final label = _Geometry._measure(text);
      final x = (plot.left + plot.width * f - label.width / 2).clamp(
        plot.left,
        plot.right - label.width,
      );
      if (x < lastRight + 8) continue;
      label.paint(canvas, Offset(x.toDouble(), plot.bottom + 7));
      lastRight = x + label.width;
    }

    final offsets = [for (final p in points) g.at(p)];
    if (offsets.length > 1) {
      final line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final o in offsets.skip(1)) {
        line.lineTo(o.dx, o.dy);
      }
      final area = Path.from(line)
        ..lineTo(offsets.last.dx, plot.bottom)
        ..lineTo(offsets.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: .20), color.withValues(alpha: .02)],
          ).createShader(plot),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    final white = Paint()..color = AppColors.surface;
    final ink = Paint()..color = color;
    if (offsets.length <= 60) {
      for (final o in offsets) {
        canvas.drawCircle(o, 3.6, white);
        canvas.drawCircle(o, 2.3, ink);
      }
    }

    void bubble(int index, {required bool withDate}) {
      final o = offsets[index], p = points[index];
      canvas.drawCircle(o, 6, white);
      canvas.drawCircle(o, 4.2, ink);
      final text = _Geometry._measure(
        '${withDate ? '${_fullDate(p.$1)} · ' : ''}${TrendChart.number(p.$2)} $unit',
        color: Colors.white,
        size: 11.5,
        weight: FontWeight.w600,
      );
      final w = text.width + 14, h = text.height + 8;
      final left = (o.dx - w / 2).clamp(0.0, size.width - w);
      final top = o.dy - h - 9 < 0 ? o.dy + 9 : o.dy - h - 9;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left.toDouble(), top, w, h),
          const Radius.circular(6),
        ),
        Paint()..color = withDate ? AppColors.text : color,
      );
      text.paint(canvas, Offset(left + 7, top + 4));
    }

    if (hover != null) {
      final x = offsets[hover!].dx;
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = AppColors.textFaint
          ..strokeWidth = 1,
      );
      bubble(hover!, withDate: true);
    } else {
      // Senza cursore resta scritto l'ultimo valore.
      bubble(offsets.length - 1, withDate: false);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.hover != hover ||
      old.color != color ||
      old.unit != unit ||
      old.points.length != points.length ||
      (points.isNotEmpty &&
          (old.points.last != points.last || old.points.first != points.first));
}
