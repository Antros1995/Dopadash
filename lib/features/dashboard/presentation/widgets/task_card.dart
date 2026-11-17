import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/presentation/app_card.dart';
import '../../../../core/presentation/mac_widgets.dart';
import '../../../../core/utils/date_formatters.dart';
import '../../../tasks/application/task_controller.dart';
import '../../../tasks/domain/dashboard_task.dart';
import '../../../../core/i18n/i18n.dart';

class DashboardTaskCard extends StatefulWidget {
  const DashboardTaskCard({
    required this.title,
    required this.icon,
    required this.group,
    required this.controller,
    this.minHeight = 234,
    this.fillAvailable = false,
    super.key,
  });

  final String title;
  final IconData icon;
  final DashboardTaskGroup group;
  final TaskController controller;
  final double minHeight;
  final bool fillAvailable;

  @override
  State<DashboardTaskCard> createState() => _DashboardTaskCardState();
}

class _DashboardTaskCardState extends State<DashboardTaskCard> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  DashboardTaskColor _newTaskColor = DashboardTaskColor.black;
  DateTime? _newTaskDueDate;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(DashboardTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Eliminare l’attività?', 'Delete the task?')),
        content: Text(
          tr(
            '“${task.title}” verrà eliminata definitivamente.',
            '“${task.title}” will be deleted permanently.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Annulla', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(tr('Elimina', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.delete(task.id);
  }

  Future<void> _addTask() async {
    final title = _textController.text;
    if (title.trim().isEmpty) return;
    final dueDate = _newTaskDueDate ?? widget.controller.selectedDate;
    _textController.clear();
    await widget.controller.addTask(
      title: title,
      group: widget.group,
      color: _newTaskColor,
      scheduledDate: dueDate,
    );
    if (mounted) setState(() => _newTaskDueDate = null);
    _focusNode.requestFocus();
  }

  Future<void> _selectDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _newTaskDueDate ?? widget.controller.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: tr('Scegli la data prevista', 'Choose the due date'),
      confirmText: tr('Conferma', 'Confirm'),
      cancelText: tr('Annulla', 'Cancel'),
    );
    if (selected != null && mounted) {
      setState(() => _newTaskDueDate = taskDateOnly(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.controller.tasksFor(widget.group);
    final card = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: widget.title,
            subtitle: tr(
              'Le attività non concluse passano automaticamente al giorno successivo.',
              'Unfinished tasks move to the next day automatically.',
            ),
            trailing: Icon(widget.icon, color: AppColors.green),
          ),
          const SizedBox(height: AppSpacing.sm),
          _TaskComposer(
            controller: _textController,
            focusNode: _focusNode,
            color: _newTaskColor,
            dueDate: _newTaskDueDate ?? widget.controller.selectedDate,
            onColorChanged: (color) => setState(() => _newTaskColor = color),
            onDueDateSelected: _selectDueDate,
            onSubmitted: _addTask,
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: widget.controller.isLoading
                ? const Center(child: CircularProgressIndicator())
                : tasks.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        tr(
                          'Nessuna attività per questa giornata.',
                          'No tasks for this day.',
                        ),
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    thickness: 6,
                    radius: const Radius.circular(8),
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(right: 12),
                      shrinkWrap: true,
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 7),
                      itemBuilder: (context, index) => _TaskRow(
                        task: tasks[index],
                        referenceDate: widget.controller.selectedDate,
                        onToggle: () =>
                            widget.controller.toggle(tasks[index].id),
                        onColorChanged: (color) =>
                            widget.controller.setColor(tasks[index].id, color),
                        onReschedule: (date) =>
                            widget.controller.reschedule(tasks[index].id, date),
                        onDelete: () => _confirmDelete(tasks[index]),
                      ),
                    ),
                  ),
          ),
          if (widget.controller.error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              tr(
                'Salvataggio non riuscito. Riprova dopo aver controllato il browser.',
                'Save failed. Check the browser and try again.',
              ),
              style: TextStyle(fontSize: 11, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
    return widget.fillAvailable
        ? card
        : SizedBox(height: widget.minHeight, child: card);
  }
}

class DashboardTaskOverviewCard extends StatefulWidget {
  const DashboardTaskOverviewCard({required this.controller, super.key});

  final TaskController controller;

  @override
  State<DashboardTaskOverviewCard> createState() =>
      _DashboardTaskOverviewCardState();
}

class _DashboardTaskOverviewCardState extends State<DashboardTaskOverviewCard> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(DashboardTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Eliminare l’attività?', 'Delete the task?')),
        content: Text(
          tr(
            '“${task.title}” verrà eliminata definitivamente.',
            '“${task.title}” will be deleted permanently.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Annulla', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(tr('Elimina', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.delete(task.id);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.controller.overviewTasks;
    final activeTasks = tasks.where((task) => !task.isCompleted).toList();
    final completedTasks = tasks.where((task) => task.isCompleted).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: tr('Tutte le attività', 'All tasks'),
            subtitle: tr(
              'Panoramica completa, ordinata per data prevista.',
              'Full overview, sorted by due date.',
            ),
            trailing: Icon(Icons.view_list_outlined, color: AppColors.green),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: tasks.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      tr('Nessuna attività presente.', 'No tasks yet.'),
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    thickness: 6,
                    radius: const Radius.circular(8),
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(right: 12),
                      children: [
                        if (activeTasks.isNotEmpty) ...[
                          _TaskOverviewSectionHeading(
                            title: tr('Attività da completare', 'Tasks to do'),
                            icon: Icons.radio_button_unchecked_rounded,
                          ),
                          const SizedBox(height: 7),
                          for (final task in activeTasks) ...[
                            _TaskRow(
                              task: task,
                              referenceDate: widget.controller.today,
                              alwaysShowDate: true,
                              showGroup: true,
                              onToggle: () => widget.controller.toggle(task.id),
                              onColorChanged: (color) =>
                                  widget.controller.setColor(task.id, color),
                              onReschedule: (date) =>
                                  widget.controller.reschedule(task.id, date),
                              onDelete: () => _confirmDelete(task),
                            ),
                            const SizedBox(height: 7),
                          ],
                        ],
                        if (completedTasks.isNotEmpty) ...[
                          if (activeTasks.isNotEmpty)
                            const SizedBox(height: AppSpacing.sm),
                          _TaskOverviewSectionHeading(
                            title: tr('Attività completate', 'Completed tasks'),
                            icon: Icons.check_circle_outline_rounded,
                          ),
                          const SizedBox(height: 7),
                          for (final task in completedTasks) ...[
                            _TaskRow(
                              task: task,
                              referenceDate: widget.controller.today,
                              alwaysShowDate: true,
                              showGroup: true,
                              onToggle: () => widget.controller.toggle(task.id),
                              onColorChanged: (color) =>
                                  widget.controller.setColor(task.id, color),
                              onReschedule: (date) =>
                                  widget.controller.reschedule(task.id, date),
                              onDelete: () => _confirmDelete(task),
                            ),
                            const SizedBox(height: 7),
                          ],
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TaskOverviewSectionHeading extends StatelessWidget {
  const _TaskOverviewSectionHeading({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: AppColors.green),
      const SizedBox(width: 7),
      Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.textMuted,
        ),
      ),
    ],
  );
}

class _TaskComposer extends StatelessWidget {
  const _TaskComposer({
    required this.controller,
    required this.focusNode,
    required this.color,
    required this.dueDate,
    required this.onColorChanged,
    required this.onDueDateSelected,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final DashboardTaskColor color;
  final DateTime dueDate;
  final ValueChanged<DashboardTaskColor> onColorChanged;
  final Future<void> Function() onDueDateSelected;
  final Future<void> Function() onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          _TaskColorMenu(color: color, onChanged: onColorChanged),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLength: 160,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmitted(),
                decoration: InputDecoration(
                  hintText: tr(
                    'Scrivi una nuova attività…',
                    'Write a new task…',
                  ),
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton.filled(
            onPressed: onSubmitted,
            tooltip: tr('Aggiungi attività', 'Add task'),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onDueDateSelected,
          icon: const Icon(Icons.event_outlined, size: 16),
          label: Text(
            tr(
              'Da fare il ${formatShortDate(dueDate)}',
              'Due ${formatShortDate(dueDate)}',
            ),
          ),
        ),
      ),
    ],
  );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.referenceDate,
    required this.onToggle,
    required this.onColorChanged,
    required this.onReschedule,
    this.onDelete,
    this.alwaysShowDate = false,
    this.showGroup = false,
  });

  final DashboardTask task;
  final DateTime referenceDate;
  final VoidCallback onToggle;
  final ValueChanged<DashboardTaskColor> onColorChanged;
  final Future<void> Function(DateTime) onReschedule;
  final VoidCallback? onDelete;
  final bool alwaysShowDate;
  final bool showGroup;

  Future<void> _selectNewDate(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: task.scheduledDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: tr('Modifica la data dell’attività', 'Change the task date'),
      confirmText: tr('Salva data', 'Save date'),
      cancelText: tr('Annulla', 'Cancel'),
    );
    if (selected != null) await onReschedule(selected);
  }

  @override
  Widget build(BuildContext context) {
    final color = taskColorValue(task.color);
    final overdue =
        !task.isCompleted && task.scheduledDate.isBefore(referenceDate);
    final showDate = true;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: task.isCompleted ? 0.58 : 1,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 2),
            MacCheck(checked: task.isCompleted, color: color, onTap: onToggle),
            const SizedBox(width: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 190;
                  final title = Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  );
                  final dateButton = _TaskDateButton(
                    date: task.scheduledDate,
                    overdue: overdue,
                    compact: compact,
                    onPressed: () => _selectNewDate(context),
                  );
                  if (compact) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 2), dateButton],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      if (showGroup) ...[
                        const SizedBox(width: 8),
                        _TaskBadge(label: taskGroupLabel(task.group)),
                      ],
                      if (showDate) ...[const SizedBox(width: 8), dateButton],
                    ],
                  );
                },
              ),
            ),
            _TaskColorMenu(
              color: task.color,
              onChanged: onColorChanged,
              compact: true,
            ),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                tooltip: tr('Elimina attività', 'Delete task'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            const SizedBox(width: 3),
          ],
        ),
      ),
    );
  }
}

class _TaskBadge extends StatelessWidget {
  const _TaskBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.greenPale,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
      ),
    ),
  );
}

class _TaskDateButton extends StatelessWidget {
  const _TaskDateButton({
    required this.date,
    required this.overdue,
    required this.compact,
    required this.onPressed,
  });

  final DateTime date;
  final bool overdue;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = overdue ? AppColors.warning : AppColors.textMuted;
    return Tooltip(
      message: tr('Modifica data attività', 'Change task date'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 5 : 7,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: overdue ? AppColors.warningSoft : AppColors.greenPale,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_calendar_outlined, size: 14, color: foreground),
                const SizedBox(width: 4),
                Text(
                  compact
                      ? formatShortDate(date)
                      : tr(
                          'Entro ${formatShortDate(date)}',
                          'By ${formatShortDate(date)}',
                        ),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String taskGroupLabel(DashboardTaskGroup group) => switch (group) {
  DashboardTaskGroup.personal => tr('Personali', 'Personal'),
  DashboardTaskGroup.work => tr('Lavoro', 'Work'),
  DashboardTaskGroup.personalWork => tr('Lavoro personale', 'Side project'),
  DashboardTaskGroup.posta => tr('Posta', 'Mail'),
};

class _TaskColorMenu extends StatelessWidget {
  const _TaskColorMenu({
    required this.color,
    required this.onChanged,
    this.compact = false,
  });

  final DashboardTaskColor color;
  final ValueChanged<DashboardTaskColor> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => PopupMenuButton<DashboardTaskColor>(
    tooltip: tr('Colore attività', 'Task colour'),
    onSelected: onChanged,
    itemBuilder: (context) => [
      for (final option in DashboardTaskColor.values)
        PopupMenuItem(
          value: option,
          child: Row(
            children: [
              _ColorDot(color: taskColorValue(option)),
              const SizedBox(width: 10),
              Text(taskColorLabel(option)),
            ],
          ),
        ),
    ],
    child: SizedBox.square(
      dimension: compact ? 38 : 42,
      child: Center(child: _ColorDot(color: taskColorValue(color))),
    ),
  );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 17,
    height: 17,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(
        color: color == AppColors.text ? AppColors.border : color,
      ),
    ),
  );
}

Color taskColorValue(DashboardTaskColor color) => switch (color) {
  DashboardTaskColor.black => AppColors.text,
  DashboardTaskColor.red => const Color(0xFFD64B4B),
  DashboardTaskColor.blue => const Color(0xFF3478C7),
  DashboardTaskColor.green => const Color(0xFF3E8F62),
  DashboardTaskColor.yellow => const Color(0xFFE0A51B),
};

String taskColorLabel(DashboardTaskColor color) => switch (color) {
  DashboardTaskColor.black => tr('Nero', 'Black'),
  DashboardTaskColor.red => tr('Rosso', 'Red'),
  DashboardTaskColor.blue => tr('Blu', 'Blue'),
  DashboardTaskColor.green => tr('Verde', 'Green'),
  DashboardTaskColor.yellow => tr('Giallo', 'Yellow'),
};
