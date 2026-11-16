import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/presentation/modular_board.dart';
import '../../../core/presentation/app_card.dart';
import '../../../core/presentation/mac_widgets.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../../core/utils/date_formatters.dart';
import '../application/task_controller.dart';
import '../domain/dashboard_task.dart';

/// Dedicated workspace for every task stored in the shared Supabase list.
///
/// [TaskController] remains the single source of truth, so changes made here
/// immediately appear in the dashboard and on every connected device.
class TodoPage extends StatefulWidget {
  const TodoPage({required this.controller, this.scope = 'local', super.key});

  final TaskController controller;
  final String scope;

  @override
  State<TodoPage> createState() => TodoPageState();
}

class TodoPageState extends State<TodoPage> {
  final _scrollController = ScrollController();
  String _section = 'Panoramica';
  void showSection(String section) => setState(() {
    _section = section;
    if (section == 'Posta') _group = DashboardTaskGroup.posta;
    _filter = section == 'Completate'
        ? _TodoFilter.completed
        : _TodoFilter.open;
  });
  final _titleController = TextEditingController();
  DashboardTaskGroup _group = DashboardTaskGroup.personal;
  DashboardTaskColor _color = DashboardTaskColor.blue;
  late DateTime _dueDate;
  _TodoFilter _filter = _TodoFilter.open;

  @override
  void initState() {
    super.initState();
    _dueDate = widget.controller.selectedDate;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _addTask() async {
    if (_titleController.text.trim().isEmpty) return;
    await widget.controller.addTask(
      title: _titleController.text,
      group: _group,
      color: _color,
      scheduledDate: _dueDate,
    );
    if (mounted) {
      _titleController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('it'),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _confirmDelete(DashboardTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare l’attività?'),
        content: Text('“${task.title}” verrà eliminata definitivamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.delete(task.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final tasks = widget.controller.overviewTasks;
        final openTasks = tasks.where((task) => !task.isCompleted).toList();
        final completedTasks = tasks.where((task) => task.isCompleted).toList();
        final filteredTasks = switch (_filter) {
          _TodoFilter.open => openTasks,
          _TodoFilter.completed => completedTasks,
          _TodoFilter.all => tasks,
        };
        final visibleTasks = filteredTasks.where((t) {
          final date = widget.controller.dateFor(t),
              today = DateUtils.dateOnly(widget.controller.today);
          return switch (_section) {
            'Personali' => t.group == DashboardTaskGroup.personal,
            'Lavorative' => t.group == DashboardTaskGroup.work,
            'Lavoro personale' => t.group == DashboardTaskGroup.personalWork,
            'Posta' => t.group == DashboardTaskGroup.posta,
            'Oggi' => DateUtils.isSameDay(date, today),
            'Questa settimana' =>
              !date.isBefore(
                    today.subtract(Duration(days: today.weekday - 1)),
                  ) &&
                  date.isBefore(today.add(Duration(days: 8 - today.weekday))),
            'Scadute' => !t.isCompleted && t.scheduledDate.isBefore(today),
            _ => true,
          };
        }).toList();
        return SingleChildScrollView(
          controller: _scrollController,
          padding: pageInsets(
            context,
            const EdgeInsets.fromLTRB(24, 22, 24, 30),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TodoHeader(
                openCount: openTasks.length,
                completedCount: completedTasks.length,
              ),
              if (_section == 'Posta')
                const Text(
                  'Promemoria del calendario dal 12/10/2026 · scadenze in ordine · riporto delle voci non spuntate · salvataggio su server e sincronizzazione in tempo reale.',
                ),
              if (widget.controller.postaSyncError != null &&
                  (_section == 'Posta' || _section == 'Panoramica'))
                const Text(
                  'Posta: sincronizzazione non disponibile, riprovo automaticamente.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              if (widget.controller.error != null)
                const Text(
                  'Connessione attività non disponibile: verifica il salvataggio.',
                  style: TextStyle(color: AppColors.danger),
                ),
              ModularBoard(
                area: 'todo',
                scope: widget.scope,
                modules: [
                  BoardModule(
                    'Nuova attività',
                    'Nuova attività',
                    _NewTaskCard(
                      titleController: _titleController,
                      group: _group,
                      color: _color,
                      dueDate: _dueDate,
                      onGroupChanged: (v) => setState(() => _group = v),
                      onColorChanged: (v) => setState(() => _color = v),
                      onDueDateSelected: _pickDueDate,
                      onSubmitted: _addTask,
                    ),
                    height: 132,
                    minHeight: 120,
                  ),
                  BoardModule(
                    'Filtri',
                    'Filtri attività',
                    _FilterBar(
                      selected: _filter,
                      openCount: openTasks.length,
                      completedCount: completedTasks.length,
                      onSelected: (v) => setState(() => _filter = v),
                    ),
                    height: 48,
                    minHeight: 44,
                  ),
                  for (final group in DashboardTaskGroup.values)
                    if (_section != 'Posta' ||
                        group == DashboardTaskGroup.posta)
                      BoardModule(
                        group.name,
                        switch (group) {
                          DashboardTaskGroup.personal => 'Personali',
                          DashboardTaskGroup.work => 'Lavorative',
                          DashboardTaskGroup.personalWork => 'Lavoro personale',
                          DashboardTaskGroup.posta => 'Posta',
                        },
                        widget.controller.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : visibleTasks
                                  .where((t) => t.group == group)
                                  .isEmpty
                            ? AppCard(
                                child: Column(
                                  children: [
                                    Text(switch (group) {
                                      DashboardTaskGroup.personal =>
                                        'Attività personali',
                                      DashboardTaskGroup.work =>
                                        'Attività lavorative',
                                      DashboardTaskGroup.personalWork =>
                                        'Attività lavoro personale',
                                      DashboardTaskGroup.posta => 'Posta',
                                    }),
                                    _EmptyTasks(filter: _filter),
                                  ],
                                ),
                              )
                            : _TaskColumn(
                                group: group,
                                tasks: visibleTasks
                                    .where((t) => t.group == group)
                                    .toList(),
                                referenceDate: widget.controller.today,
                                onToggle: widget.controller.toggle,
                                onDelete: _confirmDelete,
                              ),
                        columns: 4,
                        height: 550,
                      ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TodoHeader extends StatelessWidget {
  const _TodoHeader({required this.openCount, required this.completedCount});

  final int openCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    if (usesPhoneLayout(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('To Do', style: _pageTitle),
          const SizedBox(height: 5),
          const Text(
            'Le tue attività, sempre aggiornate.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SyncPill(),
              _CountPill(
                icon: Icons.pending_actions_outlined,
                count: openCount,
                label: 'aperte',
              ),
              _CountPill(
                icon: Icons.task_alt_rounded,
                count: completedCount,
                label: 'fatte',
              ),
            ],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('To Do', style: _pageTitle),
              const SizedBox(height: 4),
              const Text(
                'Tutte le attività in un unico spazio, aggiornato in tempo reale.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        _SyncPill(),
        const SizedBox(width: AppSpacing.sm),
        _CountPill(
          icon: Icons.pending_actions_outlined,
          count: openCount,
          label: 'aperte',
        ),
        const SizedBox(width: AppSpacing.xs),
        _CountPill(
          icon: Icons.task_alt_rounded,
          count: completedCount,
          label: 'fatte',
        ),
      ],
    );
  }
}

const _pageTitle = TextStyle(
  fontSize: 28,
  height: 1.15,
  fontWeight: FontWeight.w700,
  letterSpacing: -.56,
  color: AppColors.text,
);

class _SyncPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 8),
    child: MacChip('● Live', tone: AppColors.green),
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.icon,
    required this.count,
    required this.label,
  });
  final IconData icon;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: MacChip('$count $label'),
  );
}

class _NewTaskCard extends StatelessWidget {
  const _NewTaskCard({
    required this.titleController,
    required this.group,
    required this.color,
    required this.dueDate,
    required this.onGroupChanged,
    required this.onColorChanged,
    required this.onDueDateSelected,
    required this.onSubmitted,
  });
  final TextEditingController titleController;
  final DashboardTaskGroup group;
  final DashboardTaskColor color;
  final DateTime dueDate;
  final ValueChanged<DashboardTaskGroup> onGroupChanged;
  final ValueChanged<DashboardTaskColor> onColorChanged;
  final Future<void> Function() onDueDateSelected;
  final Future<void> Function() onSubmitted;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: titleController,
          maxLength: 160,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Nuova attività… scrivi e premi Invio',
            counterText: '',
            isDense: true,
            filled: true,
            fillColor: AppColors.fill,
            prefixIcon: const Icon(Icons.add, color: AppColors.green, size: 20),
            prefixIconConstraints: const BoxConstraints(minWidth: 38),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ChoiceMenu<DashboardTaskGroup>(
              icon: Icons.folder_outlined,
              label: taskGroupLabel(group),
              value: group,
              values: DashboardTaskGroup.values,
              labelFor: taskGroupLabel,
              onChanged: onGroupChanged,
            ),
            _ChoiceMenu<DashboardTaskColor>(
              icon: Icons.palette_outlined,
              label: taskColorLabel(color),
              value: color,
              values: DashboardTaskColor.values,
              labelFor: taskColorLabel,
              onChanged: onColorChanged,
              leadingFor: (value) => _ColorDot(color: taskColorValue(value)),
            ),
            _QuietButton(
              icon: const Icon(Icons.event_outlined, size: 15),
              label: 'Entro ${formatShortDate(dueDate)}',
              onPressed: onDueDateSelected,
            ),
            FilledButton(
              onPressed: onSubmitted,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Pulsante sobrio a fondo grigio, come i campi dell'Organizzatore.
class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.icon, required this.label, this.onPressed});
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.fill,
    borderRadius: BorderRadius.circular(AppRadius.control),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme.merge(
              data: const IconThemeData(color: AppColors.textMuted),
              child: icon,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.text),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChoiceMenu<T> extends StatelessWidget {
  const _ChoiceMenu({
    required this.icon,
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
    this.leadingFor,
  });
  final IconData icon;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;
  final Widget Function(T)? leadingFor;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    onSelected: onChanged,
    itemBuilder: (context) => [
      for (final option in values)
        PopupMenuItem(
          value: option,
          child: Row(
            children: [
              if (leadingFor != null) ...[
                leadingFor!(option),
                const SizedBox(width: 8),
              ],
              Text(labelFor(option)),
            ],
          ),
        ),
    ],
    child: _QuietButton(
      icon: leadingFor?.call(value) ?? Icon(icon, size: 15),
      label: label,
    ),
  );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.openCount,
    required this.completedCount,
    required this.onSelected,
  });
  final _TodoFilter selected;
  final int openCount;
  final int completedCount;
  final ValueChanged<_TodoFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    if (usesPhoneLayout(context)) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final filter in _TodoFilter.values)
            ChoiceChip(
              label: Text(switch (filter) {
                _TodoFilter.open => 'Da fare ($openCount)',
                _TodoFilter.completed => 'Completate ($completedCount)',
                _ => 'Tutte',
              }),
              selected: selected == filter,
              onSelected: (_) => onSelected(filter),
            ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: MacSegmented<_TodoFilter>(
        values: _TodoFilter.values,
        selected: selected,
        onSelected: onSelected,
        labelFor: (filter) => switch (filter) {
          _TodoFilter.open => 'Da fare ($openCount)',
          _TodoFilter.completed => 'Completate ($completedCount)',
          _TodoFilter.all => 'Tutte',
        },
      ),
    );
  }
}

class _TaskColumn extends StatelessWidget {
  const _TaskColumn({
    required this.group,
    required this.tasks,
    required this.referenceDate,
    required this.onToggle,
    required this.onDelete,
  });
  final DashboardTaskGroup group;
  final List<DashboardTask> tasks;
  final DateTime referenceDate;
  final Future<void> Function(String) onToggle;
  final Future<void> Function(DashboardTask) onDelete;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _GroupIcon(group: group),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                taskGroupLabel(group),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '${tasks.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Nessuna attività in questa lista.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          )
        else
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) const MacDivider(),
            _TodoTaskTile(
              task: tasks[i],
              referenceDate: referenceDate,
              onToggle: () => onToggle(tasks[i].id),
              onDelete: () => onDelete(tasks[i]),
            ),
          ],
      ],
    ),
  );
}

class _TodoTaskTile extends StatelessWidget {
  const _TodoTaskTile({
    required this.task,
    required this.referenceDate,
    required this.onToggle,
    required this.onDelete,
  });
  final DashboardTask task;
  final DateTime referenceDate;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = taskColorValue(task.color);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: task.isCompleted ? .55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MacCheck(
              checked: task.isCompleted,
              color: color,
              onTap: onToggle,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: task.isCompleted
                            ? FontWeight.w400
                            : FontWeight.w500,
                        color: task.isCompleted
                            ? AppColors.textMuted
                            : AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Tooltip(
                    message: 'Entro ${formatShortDate(task.scheduledDate)}',
                    child: MacChip.due(
                      task.scheduledDate,
                      referenceDate,
                      dueAt: task.dueAt,
                      completed: task.isCompleted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Elimina attività',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 17,
                color: AppColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupIcon extends StatelessWidget {
  const _GroupIcon({required this.group});
  final DashboardTaskGroup group;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (group) {
      DashboardTaskGroup.personal => (
        Icons.person_outline_rounded,
        const Color(0xFF5A72BA),
      ),
      DashboardTaskGroup.work => (
        Icons.work_outline_rounded,
        const Color(0xFFCB7B32),
      ),
      DashboardTaskGroup.personalWork => (
        Icons.business_center_outlined,
        AppColors.green,
      ),
      DashboardTaskGroup.posta => (Icons.inbox_outlined, AppColors.green),
    };
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 15),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks({required this.filter});
  final _TodoFilter filter;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 42,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(switch (filter) {
            _TodoFilter.open => 'Non hai attività da completare.',
            _TodoFilter.completed => 'Non hai ancora completato attività.',
            _TodoFilter.all => 'Non hai ancora creato attività.',
          }, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}

enum _TodoFilter { open, completed, all }

String taskGroupLabel(DashboardTaskGroup group) => switch (group) {
  DashboardTaskGroup.personal => 'Personali',
  DashboardTaskGroup.work => 'Lavoro',
  DashboardTaskGroup.personalWork => 'Lavoro personale',
  DashboardTaskGroup.posta => 'Posta',
};

Color taskColorValue(DashboardTaskColor color) => switch (color) {
  DashboardTaskColor.black => AppColors.text,
  DashboardTaskColor.red => const Color(0xFFD64B4B),
  DashboardTaskColor.blue => const Color(0xFF3478C7),
  DashboardTaskColor.green => const Color(0xFF3E8F62),
  DashboardTaskColor.yellow => const Color(0xFFE0A51B),
};

String taskColorLabel(DashboardTaskColor color) => switch (color) {
  DashboardTaskColor.black => 'Nero',
  DashboardTaskColor.red => 'Rosso',
  DashboardTaskColor.blue => 'Blu',
  DashboardTaskColor.green => 'Verde',
  DashboardTaskColor.yellow => 'Giallo',
};
