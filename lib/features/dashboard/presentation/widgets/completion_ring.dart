import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/i18n/i18n.dart';

class CompletionRing extends StatelessWidget {
  const CompletionRing({
    required this.percentage,
    required this.completed,
    required this.total,
    this.diameter = 270,
    super.key,
  });

  final int percentage;
  final int completed;
  final int total;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr(
        'Completamento $percentage per cento, $completed su $total',
        'Completion $percentage percent, $completed of $total',
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: percentage / 100),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => SizedBox.square(
          dimension: diameter,
          child: CustomPaint(
            painter: _RingPainter(value),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$percentage%',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: 50,
                      letterSpacing: -1.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      '$completed di $total completate',
                      '$completed of $total done',
                    ),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 10;
    const strokeWidth = 11.0;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.greenSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    canvas.drawArc(
      bounds,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0, 1),
      false,
      Paint()
        ..color = AppColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.value != value;
}
