import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../app/theme.dart';
import '../../../../core/presentation/app_card.dart';
import '../../../../core/presentation/mac_widgets.dart';
import '../../../../core/utils/date_formatters.dart';
import '../../../fitbit/domain/fitbit_day.dart';
import '../../../routines/application/routine_controller.dart';
import '../../../tasks/application/task_controller.dart';
import '../../../tasks/domain/dashboard_task.dart';
import 'routine_tile.dart';

class HomeHeading extends StatelessWidget {
  const HomeHeading({
    required this.title,
    required this.icon,
    this.color = AppColors.green,
    this.action,
    super.key,
  });
  final String title;
  final IconData icon;
  final Color color;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 22, color: color),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      ?action,
    ],
  );
}

class HomeLink extends StatelessWidget {
  const HomeLink({required this.label, required this.onTap, super.key});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: AppColors.textMuted,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      minimumSize: const Size(0, 28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 11),
    ),
    child: Text(label),
  );
}

class HomeHero extends StatelessWidget {
  const HomeHero({
    required this.date,
    required this.day,
    required this.onSelectDate,
    super.key,
  });
  final DateTime date;
  final FitbitDay? day;
  final ValueChanged<DateTime> onSelectDate;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 700;
      final sleep = day?.sleepMinutes;
      final subtitle = sleep != null && sleep > 0
          ? '${sleep ~/ 60}h ${sleep % 60}m di sonno registrato. La tua giornata, a colpo d’occhio.'
          : 'Salute, abitudini e impegni. Tutto nel tuo spazio personale.';
      final controls = Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Giorno precedente',
              onPressed: () =>
                  onSelectDate(date.subtract(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_left, size: 19),
            ),
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) onSelectDate(picked);
              },
              child: Text(
                formatShortDate(date),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Giorno successivo',
              onPressed: () => onSelectDate(date.add(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_right, size: 19),
            ),
            HomeLink(label: 'Oggi', onTap: () => onSelectDate(DateTime.now())),
          ],
        ),
      );
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDE8E9)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/alpine-header.png',
                fit: BoxFit.cover,
                alignment: const Alignment(0, -.1),
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFFE6F1ED)),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: .97),
                      Colors.white.withValues(alpha: .50),
                      Colors.white.withValues(alpha: .95),
                    ],
                    stops: const [0, .52, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 24,
                vertical: 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              capitalize(formatItalianDate(date)),
                              style: const TextStyle(
                                color: Color(0xFF078454),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'La tua vita, in equilibrio.',
                              style: TextStyle(
                                fontSize: compact ? 24 : 29,
                                height: 1.15,
                                letterSpacing: -.9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!compact) ...[const SizedBox(width: 20), controls],
                    ],
                  ),
                  if (compact) ...[
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: controls,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class HomeRing extends StatelessWidget {
  const HomeRing({
    required this.value,
    required this.label,
    required this.color,
    this.size = 110,
    this.suffix = '',
    super.key,
  });
  final double value;
  final String label;
  final Color color;
  final double size;
  final String suffix;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label ${value.round()}$suffix',
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RingPainter(value.clamp(0, 100) / 100, color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.round()}$suffix',
                style: TextStyle(
                  fontSize: size * .25,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppColors.text),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.ratio, this.color);
  final double ratio;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(7);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: .13);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, paint);
    if (ratio > 0) {
      paint.color = Colors.white;
      paint.shader = SweepGradient(
        colors: [color.withValues(alpha: .65), color],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * ratio, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      ratio != old.ratio || color != old.color;
}

class HomeRoutineCard extends StatelessWidget {
  const HomeRoutineCard({required this.controller, super.key});
  final RoutineController controller;
  void _all(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 570,
        height: 640,
        child: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                HomeHeading(
                  title: 'Le tue routine',
                  icon: Icons.task_alt,
                  action: IconButton(
                    tooltip: 'Chiudi',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final routine in controller.routines)
                        RoutineTile(
                          definition: routine,
                          entry: controller.entryFor(routine.id),
                          onToggle: () => controller.toggleRoutine(routine.id),
                        ),
                    ],
                  ),
                ),
                if (controller.syncError != null)
                  TextButton(
                    onPressed: controller.retrySave,
                    child: const Text('Salvataggio non riuscito · Riprova'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = controller.progress;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeHeading(
            title: DateUtils.isSameDay(controller.selectedDate, DateTime.now())
                ? 'Routine di oggi'
                : 'Routine del giorno',
            icon: Icons.track_changes,
            action: controller.loadError == null && !controller.isLoading
                ? HomeLink(label: 'Vedi tutte ›', onTap: () => _all(context))
                : null,
          ),
          const SizedBox(height: 5),
          Text(
            controller.isLoading
                ? 'Caricamento…'
                : controller.loadError != null
                ? 'Dati non caricati'
                : '${p.completedCount} di ${p.totalCount} completate',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: controller.isLoading
                ? const Center(child: CircularProgressIndicator())
                : controller.loadError != null
                ? Center(
                    child: TextButton(
                      onPressed: controller.load,
                      child: const Text('Routine non disponibili · Riprova'),
                    ),
                  )
                : controller.routines.isEmpty
                ? const Center(child: Text('Nessuna routine configurata.'))
                : LayoutBuilder(
                    builder: (context, box) {
                      final small = box.maxWidth < 390;
                      return Row(
                        children: [
                          Tooltip(
                            message:
                                'Punteggio ponderato delle routine, con le regole già condivise con l’app mobile.',
                            child: HomeRing(
                              value: p.percentage.toDouble(),
                              label: 'Punteggio',
                              color: AppColors.green,
                              size: small ? 102 : 136,
                              suffix: '%',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: LayoutBuilder(
                                builder: (context, listBox) {
                                  final two = listBox.maxWidth >= 230;
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 0,
                                    children: [
                                      for (final routine in controller.routines)
                                        SizedBox(
                                          width: two
                                              ? (listBox.maxWidth - 8) / 2
                                              : listBox.maxWidth,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            onTap: () => controller
                                                .toggleRoutine(routine.id),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    controller
                                                            .entryFor(
                                                              routine.id,
                                                            )
                                                            .isCompleted
                                                        ? Icons.check_circle
                                                        : Icons
                                                              .radio_button_unchecked,
                                                    size: 18,
                                                    color:
                                                        controller
                                                            .entryFor(
                                                              routine.id,
                                                            )
                                                            .isCompleted
                                                        ? AppColors.green
                                                        : AppColors.textMuted,
                                                  ),
                                                  const SizedBox(width: 7),
                                                  Expanded(
                                                    child: Text(
                                                      routine.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (controller.isSaving)
            const Text('Salvataggio…', style: TextStyle(fontSize: 10)),
          if (controller.syncError != null)
            HomeLink(
              label: 'Salvataggio non riuscito · Riprova',
              onTap: controller.retrySave,
            ),
        ],
      ),
    );
  }
}

class HomeTaskPreview extends StatefulWidget {
  const HomeTaskPreview({
    required this.title,
    required this.group,
    required this.controller,
    required this.onOpen,
    super.key,
  });
  final String title;
  final DashboardTaskGroup group;
  final TaskController controller;
  final VoidCallback onOpen;
  @override
  State<HomeTaskPreview> createState() => _HomeTaskPreviewState();
}

class _HomeTaskPreviewState extends State<HomeTaskPreview> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tasks = controller.tasksFor(widget.group, includeUpcoming: true);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeading(
            title: widget.title,
            icon: widget.group == DashboardTaskGroup.posta
                ? Icons.inbox_outlined
                : widget.group == DashboardTaskGroup.personal
                ? Icons.person_outline
                : Icons.work_outline,
            action: HomeLink(label: 'Vedi tutte ›', onTap: widget.onOpen),
          ),
          if (controller.isLoading) const LinearProgressIndicator(minHeight: 2),
          if (widget.group == DashboardTaskGroup.posta &&
              controller.postaSyncError != null)
            const Text(
              'Posta non sincronizzata · riprovo automaticamente',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          if (controller.error != null)
            const Text(
              'Riconnessione automatica · ultimi dati disponibili',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          Expanded(
            child: tasks.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        controller.isLoading || controller.error != null
                            ? 'Sincronizzazione delle attività…'
                            : 'Nessuna attività da fare.',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    thickness: 6,
                    radius: const Radius.circular(8),
                    child: ListView.builder(
                      controller: _scroll,
                      primary: false,
                      padding: const EdgeInsets.only(right: 10),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            border: index == 0
                                ? null
                                : const Border(
                                    top: BorderSide(color: AppColors.border),
                                  ),
                          ),
                          child: Row(
                            children: [
                              MacCheck(
                                checked: task.isCompleted,
                                size: 17,
                                onTap: () => controller.toggle(task.id),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Tooltip(
                                  message: task.title,
                                  child: Text(
                                    task.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: task.isCompleted
                                          ? AppColors.textMuted
                                          : AppColors.text,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              MacChip.due(
                                task.scheduledDate,
                                controller.today,
                                dueAt: task.dueAt,
                                completed: task.isCompleted,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onOpen,
              icon: const Icon(Icons.add, size: 15),
              label: const Text(
                'Aggiungi attività',
                style: TextStyle(fontSize: 11),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 27),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
