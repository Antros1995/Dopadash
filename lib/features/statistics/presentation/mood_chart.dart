import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../domain/perception_statistics.dart';

/// Segno di un'emozione: +1 piacevole, −1 difficile, valori intermedi per
/// quelle sfumate. Moltiplicato per l'intensità (1–5) dà il punteggio di un
/// check-in; la media dei check-in dà il tono della giornata, da −5 a +5.
const emotionValence = <String, double>{
  'happy': 1,
  'joy': 1,
  'content': 1,
  'satisfied': 1,
  'calm': 1,
  'grateful': 1,
  'inspired': 1,
  'excited': 1,
  'hyperfocus': .5,
  'neutral': 0,
  'tired': -.5,
  'bored': -.5,
  'confused': -.5,
  'restless': -1,
  'anxious': -1,
  'stressed': -1,
  'overwhelmed': -1,
  'irritated': -1,
  'angry': -1,
  'sad': -1,
  'afraid': -1,
};

/// Tono di ogni giornata, per chiave data (yyyy-MM-dd).
Map<String, double> dailyMood(Iterable<PerceptionEntry> entries) {
  final sums = <String, double>{}, counts = <String, int>{};
  for (final e in entries) {
    final valence = emotionValence[e.emotion];
    if (valence == null || !e.hasRating) continue;
    sums[e.dateKey] = (sums[e.dateKey] ?? 0) + valence * e.intensity;
    counts[e.dateKey] = (counts[e.dateKey] ?? 0) + 1;
  }
  return {for (final k in sums.keys) k: sums[k]! / counts[k]!};
}

/// Barre verdi sopra lo zero per le giornate positive, rosse sotto per
/// quelle negative.
class MoodChart extends StatefulWidget {
  const MoodChart({
    required this.dates,
    required this.mood,
    required this.keyFor,
    this.height = 190,
    super.key,
  });
  final List<DateTime> dates;
  final Map<String, double> mood;
  final String Function(DateTime) keyFor;
  final double height;

  static const up = Color(0xFF0E9F6E), down = Color(0xFFD64545);
  static String signed(double v) =>
      '${v > 0
          ? '+'
          : v < 0
          ? '−'
          : ''}${v.abs().toStringAsFixed(1).replaceAll('.', ',')}';

  @override
  State<MoodChart> createState() => _MoodChartState();
}

class _MoodChartState extends State<MoodChart> {
  int? _hover;
  static const _left = 30.0;

  void _point(Offset local, double width) {
    final slot = (width - _left) / widget.dates.length;
    final i = ((local.dx - _left) / slot).floor();
    final next = i >= 0 && i < widget.dates.length ? i : null;
    if (next != _hover) setState(() => _hover = next);
  }

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final d in widget.dates) widget.mood[widget.keyFor(d)],
    ];
    final known = values.whereType<double>().toList();
    if (known.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text(
          'Nessun check-in nel periodo: il tono delle giornate comparirà qui.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }
    final positive = known.where((v) => v > .5).length;
    final negative = known.where((v) => v < -.5).length;
    final mean = known.reduce((a, b) => a + b) / known.length;
    final hover = _hover;
    final hovered = hover == null ? null : values[hover];
    String day(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, box) => MouseRegion(
              onHover: (e) => _point(e.localPosition, box.maxWidth),
              onExit: (_) => setState(() => _hover = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (e) => _point(e.localPosition, box.maxWidth),
                onHorizontalDragUpdate: (e) =>
                    _point(e.localPosition, box.maxWidth),
                child: CustomPaint(
                  size: Size(box.maxWidth, widget.height),
                  painter: _MoodPainter(
                    values,
                    day(widget.dates.first),
                    day(widget.dates.last),
                    hover,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hover != null
              ? '${day(widget.dates[hover])} · ${hovered == null ? 'nessun check-in' : 'tono ${MoodChart.signed(hovered)} su 5'}'
              : '$positive giornate positive · $negative negative · ${known.length - positive - negative} neutre · media ${MoodChart.signed(mean)}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Ogni check-in vale la sua intensità con il segno dell’emozione (felice 3 = +3, triste 4 = −4); la barra è la media della giornata.',
          style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _MoodPainter extends CustomPainter {
  _MoodPainter(this.values, this.first, this.last, this.hover);
  final List<double?> values;
  final String first, last;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0, bottom = 18.0, top = 4.0;
    final plot = Rect.fromLTRB(left, top, size.width, size.height - bottom);
    final zero = plot.center.dy;
    void text(String s, Offset o, {bool right = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, right ? o - Offset(tp.width, 0) : o);
    }

    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (final (label, y) in [
      ('+5', plot.top),
      ('0', zero),
      ('−5', plot.bottom),
    ]) {
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      text(label, Offset(0, y - 6));
    }
    final slot = plot.width / values.length;
    final bar = math.max(1.5, math.min(16.0, slot * .72));
    if (hover != null) {
      canvas.drawRect(
        Rect.fromLTWH(plot.left + slot * hover!, plot.top, slot, plot.height),
        Paint()..color = AppColors.fill,
      );
    }
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final h = math.max(2.0, plot.height / 2 * (v.abs() / 5).clamp(0, 1));
      final x = plot.left + slot * i + (slot - bar) / 2;
      final neutral = v.abs() <= .5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, v >= 0 ? zero - h : zero, bar, h),
          Radius.circular(math.min(3, bar / 2)),
        ),
        Paint()
          ..color = neutral
              ? AppColors.textFaint
              : v > 0
              ? MoodChart.up
              : MoodChart.down,
      );
    }
    canvas.drawLine(
      Offset(plot.left, zero),
      Offset(plot.right, zero),
      Paint()
        ..color = AppColors.textMuted
        ..strokeWidth = 1,
    );
    text(first, Offset(plot.left, plot.bottom + 4));
    text(last, Offset(plot.right, plot.bottom + 4), right: true);
  }

  @override
  bool shouldRepaint(_MoodPainter old) =>
      old.hover != hover || old.values != values;
}
