import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/presentation/mac_widgets.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../dashboard/presentation/widgets/routine_tile.dart'
    show routineIcon;
import '../../routines/application/routine_controller.dart';
import '../../routines/domain/routine.dart';
import '../application/daily_controller.dart';
import '../domain/daily_models.dart';
import 'daily_widgets.dart';
import 'screen_time_dialog.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/i18n/names.dart';

/// Quotidianità: il cellulare di ieri, la coppa, le abitudini da spuntare e i
/// check-in di emozioni, concentrazione e movimento. Una cosa alla volta, con
/// lo stato sempre visibile.
class DailyPage extends StatefulWidget {
  const DailyPage({
    required this.routines,
    required this.daily,
    required this.onSelectDate,
    this.nutrition,
    super.key,
  });
  final RoutineController routines;
  final DailyController daily;
  final ValueChanged<DateTime> onSelectDate;

  /// La sezione Alimentazione (il piano con i cibi da spuntare).
  final Widget? nutrition;

  @override
  State<DailyPage> createState() => DailyPageState();
}

class DailyPageState extends State<DailyPage> {
  final _scroll = ScrollController();

  /// Vero quando si guarda l'Alimentazione al posto della giornata.
  bool _food = false;
  final _keys = {
    for (final s in const [
      'Cellulare',
      'Abitudini',
      'Emozioni',
      'Concentrazione',
      'Movimento',
    ])
      s: GlobalKey(),
  };

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void showSection(String section) {
    final food = section == 'Alimentazione' && widget.nutrition != null;
    if (food != _food) {
      setState(() => _food = food);
      if (!food) {
        // La giornata torna visibile al prossimo fotogramma.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => showSection(section),
        );
      }
      return;
    }
    if (food) return;
    final target = _keys[section]?.currentContext;
    if (target == null) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        alignment: .04,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.routines, widget.daily]),
    builder: (context, _) {
      final routines = widget.routines, daily = widget.daily, day = daily.day;
      final progress = routines.progress;
      final steps = <(String, bool, String)>[
        ('Cellulare', day.screenTime != null, sectionLabel('Cellulare')),
        (
          'Abitudini',
          progress.totalCount > 0 &&
              routines.routines.every((r) => routines.entryFor(r.id).isMarked),
          '${sectionLabel('Abitudini')} ${progress.completedCount}/${progress.totalCount}',
        ),
        ('Emozioni', day.emotions.isNotEmpty, sectionLabel('Emozioni')),
        (
          'Concentrazione',
          day.dayConcentration.isNotEmpty,
          sectionLabel('Concentrazione'),
        ),
        ('Movimento', day.movement != null, sectionLabel('Movimento')),
      ];
      final done = steps.where((s) => s.$2).length;
      final switcher = widget.nutrition == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: MacSegmented<bool>(
                values: const [false, true],
                selected: _food,
                labelFor: (food) => food
                    ? tr('🍽 Alimentazione', '🍽 Nutrition')
                    : tr('☀️ Giornata', '☀️ Day'),
                onSelected: (food) => setState(() => _food = food),
              ),
            );
      if (_food && widget.nutrition != null) {
        final insets = pageInsets(
          context,
          const EdgeInsets.fromLTRB(24, 22, 24, 0),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: insets.copyWith(bottom: 10),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(pageName(8), style: dailyPageTitle),
                      const SizedBox(height: 10),
                      switcher!,
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: widget.nutrition!),
          ],
        );
      }
      return SingleChildScrollView(
        controller: _scroll,
        padding: pageInsets(context, const EdgeInsets.fromLTRB(24, 22, 24, 40)),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DailyHeader(
                  title: pageName(8),
                  subtitle: done == steps.length
                      ? tr(
                          'Giornata completa: hai registrato tutto. ✨',
                          'Day complete: you logged everything. ✨',
                        )
                      : tr(
                          '${weekdayDate(daily.date)} · $done di ${steps.length} cose registrate',
                          '${weekdayDate(daily.date)} · $done of ${steps.length} things logged',
                        ),
                  date: daily.date,
                  today: daily.today,
                  onSelectDate: widget.onSelectDate,
                ),
                if (switcher != null) ...[const SizedBox(height: 10), switcher],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final step in steps)
                      InkWell(
                        onTap: () => showSection(step.$1),
                        borderRadius: BorderRadius.circular(6),
                        child: StatusChip(done: step.$2, label: step.$3),
                      ),
                  ],
                ),
                if (daily.error != null ||
                    routines.loadError != null ||
                    routines.syncError != null)
                  DailyErrorBanner(
                    onRetry: () {
                      daily.refresh();
                      routines.syncError != null
                          ? routines.retrySave()
                          : routines.load();
                    },
                  ),
                const SizedBox(height: 16),
                TwoColumns(
                  left: KeyedSubtree(
                    key: _keys['Cellulare'],
                    child: _ScreenTimeCard(daily: daily),
                  ),
                  right: _MedalCard(routines: routines),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _keys['Abitudini'],
                  child: _HabitsCard(routines: routines),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _keys['Emozioni'],
                  child: _EmotionsCard(daily: daily),
                ),
                const SizedBox(height: 12),
                TwoColumns(
                  left: KeyedSubtree(
                    key: _keys['Concentrazione'],
                    child: _ConcentrationCard(daily: daily),
                  ),
                  right: KeyedSubtree(
                    key: _keys['Movimento'],
                    child: _MovementCard(daily: daily),
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

// ---------------------------------------------------------------- cellulare

class _ScreenTimeCard extends StatefulWidget {
  const _ScreenTimeCard({required this.daily});
  final DailyController daily;
  @override
  State<_ScreenTimeCard> createState() => _ScreenTimeCardState();
}

class _ScreenTimeCardState extends State<_ScreenTimeCard> {
  final _field = TextEditingController();
  String? _invalid;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _quickSave() async {
    final minutes = parseMinutes(_field.text);
    if (minutes == null) {
      setState(
        () => _invalid = tr(
          'Scrivi ore e minuti, per esempio 2:15',
          'Write hours and minutes, for example 2:15',
        ),
      );
      return;
    }
    setState(() => _invalid = null);
    if (await widget.daily.saveScreenTime(ScreenTime(totalMinutes: minutes))) {
      _field.clear();
    }
  }

  Future<void> _edit() async {
    final result = await showScreenTimeDialog(
      context,
      widget.daily.day.screenTime,
    );
    if (result != null) await widget.daily.saveScreenTime(result.value);
  }

  @override
  Widget build(BuildContext context) {
    final time = widget.daily.day.screenTime;
    final usage = shiftDays(widget.daily.date, -1);
    final when = widget.daily.isToday
        ? tr('ieri', 'yesterday')
        : tr(
            'il ${usage.day.toString().padLeft(2, '0')}/${usage.month.toString().padLeft(2, '0')}',
            'on ${usage.day.toString().padLeft(2, '0')}/${usage.month.toString().padLeft(2, '0')}',
          );
    return DailySection(
      icon: Icons.smartphone,
      color: dailyBlue,
      title: widget.daily.isToday
          ? tr('Cellulare di ieri', 'Yesterday’s phone use')
          : tr('Cellulare di quel giorno prima', 'Phone use the day before'),
      status: StatusChip(
        done: time != null,
        label: time != null
            ? tr('Registrato', 'Logged')
            : tr('Da inserire', 'To add'),
      ),
      child: time == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'Quanto hai usato il telefono $when?',
                    'How much did you use your phone $when?',
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _field,
                        keyboardType: TextInputType.datetime,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _quickSave(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          hintText: '02:15',
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.fill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _quickSave,
                      child: Text(tr('Salva', 'Save')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _invalid ??
                      tr(
                        'Ore:minuti dalle impostazioni del telefono. Dopo puoi togliere le app che non contano.',
                        'Hours:minutes from your phone’s settings. Then you can remove the apps that don’t count.',
                      ),
                  style: TextStyle(
                    fontSize: 12,
                    color: _invalid == null
                        ? AppColors.textMuted
                        : AppColors.danger,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMinutes(time.countedMinutes),
                      style: const TextStyle(
                        fontSize: 40,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: EdgeInsets.only(bottom: 5),
                      child: Text(
                        tr('conteggiate', 'counted'),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _edit,
                      child: Text(tr('Modifica', 'Edit')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    MacChip(
                      '${time.medal.emoji} ${time.medal.label}',
                      tone: time.medal == ScreenTimeMedal.tooMuch
                          ? AppColors.danger
                          : dailyBlue,
                    ),
                    MacChip(
                      tr(
                        '+${time.medal.bonus.toStringAsFixed(1).replaceAll('.0', '')} punti',
                        '+${time.medal.bonus.toStringAsFixed(1).replaceAll('.0', '')} points',
                      ),
                      tone: time.medal.bonus > 0 ? AppColors.green : null,
                    ),
                    MacChip(
                      tr(
                        'totale ${formatMinutes(time.totalMinutes)}',
                        'total ${formatMinutes(time.totalMinutes)}',
                      ),
                    ),
                    if (time.exclusions.isNotEmpty)
                      MacChip(
                        '${time.exclusions.length} ${time.exclusions.length == 1 ? tr('esclusa', 'excluded') : tr('escluse', 'excluded')} · ${formatMinutes(time.excludedMinutes)}',
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

// -------------------------------------------------------------------- coppa

class _MedalCard extends StatelessWidget {
  const _MedalCard({required this.routines});
  final RoutineController routines;

  @override
  Widget build(BuildContext context) {
    final p = routines.progress;
    final medal = p.isTracked ? DayMedal.fromRate(p.rate) : DayMedal.none;
    final next = medal.next;
    final missing = next == null
        ? 0.0
        : next.threshold / 100 * p.maximumPoints - p.earnedPoints;
    final tone = switch (medal) {
      DayMedal.diamond => dailyBlue,
      DayMedal.platinum => dailyPurple,
      DayMedal.gold => const Color(0xFFD99A00),
      DayMedal.silver => const Color(0xFF7C8794),
      DayMedal.bronze => const Color(0xFFB7693A),
      DayMedal.none => AppColors.textMuted,
    };
    return DailySection(
      icon: Icons.emoji_events_outlined,
      color: const Color(0xFFD99A00),
      title: tr('Coppa di oggi', 'Today’s cup'),
      status: MacChip('${p.percentage}%', tone: p.isTracked ? tone : null),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 78,
            height: 78,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: .13),
              border: Border.all(color: tone.withValues(alpha: .45), width: 2),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, a) =>
                  ScaleTransition(scale: a, child: child),
              child: Text(
                medal.emoji,
                key: ValueKey(medal),
                style: const TextStyle(fontSize: 38),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medal.label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
                    color: medal == DayMedal.none ? AppColors.text : tone,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr(
                    '${p.completedCount} di ${p.totalCount} abitudini fatte',
                    '${p.completedCount} of ${p.totalCount} habits done',
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.rate.clamp(0, 1).toDouble(),
                    minHeight: 6,
                    backgroundColor: AppColors.fill,
                    color: medal == DayMedal.none ? AppColors.green : tone,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  next == null
                      ? tr(
                          'Massimo raggiunto. Grande giornata!',
                          'Top level reached. Great day!',
                        )
                      : tr(
                          'Ancora ${missing <= 1 ? 'pochissimo' : '${missing.ceil()} punti'} per ${next.emoji} ${next.label}',
                          '${missing <= 1 ? 'Almost there' : '${missing.ceil()} more points'} for ${next.emoji} ${next.label}',
                        ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- abitudini

class _HabitsCard extends StatefulWidget {
  const _HabitsCard({required this.routines});
  final RoutineController routines;
  @override
  State<_HabitsCard> createState() => _HabitsCardState();
}

class _HabitsCardState extends State<_HabitsCard> {
  final _newHabit = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _newHabit.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _newHabit.text.trim();
    if (name.isEmpty) return;
    _newHabit.clear();
    await widget.routines.addRoutine(name: name);
  }

  Future<void> _remove(RoutineDefinition routine) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          tr('Togliere “${routine.name}”?', 'Remove “${routine.name}”?'),
        ),
        content: Text(
          tr(
            'Non comparirà più da questo giorno in poi. Lo storico dei giorni passati resta.',
            'It won’t show up from this day on. The history of past days stays.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Annulla', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(tr('Togli', 'Remove')),
          ),
        ],
      ),
    );
    if (ok == true) await widget.routines.removeRoutine(routine.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.routines, all = c.routines;
    final todo = [
      for (final r in all)
        if (!c.entryFor(r.id).isMarked) r,
    ];
    final done = [
      for (final r in all)
        if (c.entryFor(r.id).status == RoutineStatus.ok) r,
    ];
    final skipped = [
      for (final r in all)
        if (c.entryFor(r.id).status == RoutineStatus.ko) r,
    ];
    Widget rows(List<RoutineDefinition> list) => Column(
      children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const MacDivider(indent: 40),
          _HabitRow(
            key: ValueKey(list[i].id),
            routine: list[i],
            entry: c.entryFor(list[i].id),
            editing: _editing,
            onStatus: (s) => c.setStatus(list[i].id, s),
            onRemove: () => _remove(list[i]),
          ),
        ],
      ],
    );
    Widget area(
      String title,
      Color tone,
      Color background,
      List<RoutineDefinition> list,
    ) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$title · ${list.length}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
          const SizedBox(height: 2),
          rows(list),
        ],
      ),
    );
    return DailySection(
      icon: Icons.checklist_rounded,
      title: sectionLabel('Abitudini'),
      status: StatusChip(
        done: todo.isEmpty && all.isNotEmpty,
        label: todo.isEmpty && all.isNotEmpty
            ? tr('Tutte segnate', 'All marked')
            : tr('${todo.length} da fare', '${todo.length} to do'),
      ),
      action: TextButton(
        onPressed: () => setState(() => _editing = !_editing),
        child: Text(_editing ? tr('Fine', 'Done') : tr('Modifica', 'Edit')),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.isLoading && all.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            if (todo.isNotEmpty)
              rows(todo)
            else if (all.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  tr(
                    'Niente più da fare per oggi. 🎉',
                    'Nothing left for today. 🎉',
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.green,
                  ),
                ),
              ),
            if (_editing || all.isEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newHabit,
                      maxLength: 60,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _add(),
                      decoration: InputDecoration(
                        hintText: tr(
                          'Nuova abitudine… scrivi e premi Invio',
                          'New habit… type and press Enter',
                        ),
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.fill,
                        prefixIcon: const Icon(
                          Icons.add,
                          color: AppColors.green,
                          size: 20,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 38,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _add,
                    child: Text(tr('Aggiungi', 'Add')),
                  ),
                ],
              ),
            ],
            if (done.isNotEmpty)
              area(
                tr('Fatte', 'Done'),
                AppColors.green,
                AppColors.greenSoft,
                done,
              ),
            if (skipped.isNotEmpty)
              area(
                tr('Non fatte', 'Not done'),
                AppColors.danger,
                AppColors.dangerSoft,
                skipped,
              ),
          ],
        ),
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({
    required this.routine,
    required this.entry,
    required this.editing,
    required this.onStatus,
    required this.onRemove,
    super.key,
  });
  final RoutineDefinition routine;
  final RoutineEntry entry;
  final bool editing;
  final ValueChanged<RoutineStatus> onStatus;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Qui solo fatto / non fatto: i dettagli (scheda, tipo di allenamento)
    // si scelgono nella scheda Sport.
    final status = entry.status;
    final minutes = entry.completionTimeMinutes;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (status == RoutineStatus.ko)
                InkWell(
                  onTap: () => onStatus(RoutineStatus.unmarked),
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.cancel,
                      size: 26,
                      color: AppColors.danger,
                    ),
                  ),
                )
              else
                MacCheck(
                  checked: status == RoutineStatus.ok,
                  size: 24,
                  color: AppColors.green,
                  label: routine.name,
                  onTap: () => onStatus(
                    status == RoutineStatus.ok
                        ? RoutineStatus.unmarked
                        : RoutineStatus.ok,
                  ),
                ),
              const SizedBox(width: 10),
              Icon(
                routineIcon(routine.iconKey),
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: status == RoutineStatus.unmarked
                      ? () => onStatus(RoutineStatus.ok)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      routine.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: status == RoutineStatus.unmarked
                            ? AppColors.text
                            : status == RoutineStatus.ok
                            ? const Color(0xFF0B6B4A)
                            : AppColors.danger,
                      ),
                    ),
                  ),
                ),
              ),
              if (status == RoutineStatus.ok && minutes != null)
                MacChip(formatMinutes(minutes), tone: AppColors.green),
              if (editing)
                IconButton(
                  onPressed: onRemove,
                  tooltip: tr(
                    'Togli ${routine.name}',
                    'Remove ${routine.name}',
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    size: 20,
                    color: AppColors.danger,
                  ),
                )
              else if (status == RoutineStatus.unmarked)
                TextButton(
                  onPressed: () => onStatus(RoutineStatus.ko),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    tr('Non fatta', 'Not done'),
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- emozioni

class _EmotionsCard extends StatefulWidget {
  const _EmotionsCard({required this.daily});
  final DailyController daily;
  @override
  State<_EmotionsCard> createState() => _EmotionsCardState();
}

class _EmotionsCardState extends State<_EmotionsCard> {
  DailyEmotion? _emotion;
  int _intensity = 3;
  DailyEnergy _energy = DailyEnergy.medium;
  int? _concentration;
  bool _saving = false;

  static Color toneColor(EmotionTone tone) => switch (tone) {
    EmotionTone.good => AppColors.green,
    EmotionTone.neutral => dailyBlue,
    EmotionTone.hard => macOrange,
  };

  Future<void> _save() async {
    final emotion = _emotion;
    if (emotion == null || _saving) return;
    setState(() => _saving = true);
    final ok = await widget.daily.addEmotion(
      emotion: emotion,
      intensity: _intensity,
      energy: _energy,
      concentration: _concentration,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _emotion = null;
        _intensity = 3;
        _energy = DailyEnergy.medium;
        _concentration = null;
      }
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              '${emotion.emoji} Check-in salvato alle ${clock(DateTime.now())}',
              '${emotion.emoji} Check-in saved at ${clock(DateTime.now())}',
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.daily.day.emotions;
    final last = entries.isEmpty ? null : entries.last;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),
    );
    return DailySection(
      icon: Icons.favorite_border,
      color: const Color(0xFFE5484D),
      title: tr('Come stai adesso?', 'How do you feel right now?'),
      status: StatusChip(
        done: last != null,
        label: last == null
            ? tr('Nessun check-in', 'No check-ins')
            : tr(
                '${entries.length} check-in · ultimo ${clock(last.recordedAt)}',
                '${entries.length} ${entries.length == 1 ? 'check-in' : 'check-ins'} · latest ${clock(last.recordedAt)}',
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _emotion == null
                ? tr(
                    'Tocca l’emozione che senti di più in questo momento.',
                    'Tap the emotion you feel most right now.',
                  )
                : tr(
                    'Hai scelto ${_emotion!.emoji} ${_emotion!.label}: completa qui sotto e salva.',
                    'You picked ${_emotion!.emoji} ${_emotion!.label}: finish below and save.',
                  ),
            style: const TextStyle(fontSize: 13.5, color: AppColors.text),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final emotion in DailyEmotion.values)
                if (emotion != DailyEmotion.noData)
                  ChoicePill(
                    leading: emotion.emoji,
                    label: emotion.label,
                    selected: _emotion == emotion,
                    color: toneColor(emotion.tone),
                    onTap: () => setState(
                      () => _emotion = _emotion == emotion ? null : emotion,
                    ),
                  ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _emotion == null
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label(tr('Quanto è intensa?', 'How intense is it?')),
                      LevelScale(
                        value: _intensity,
                        color: toneColor(_emotion!.tone),
                        labels: {
                          1: tr('Appena accennata', 'Barely there'),
                          2: tr('Leggera', 'Mild'),
                          3: tr('Media', 'Medium'),
                          4: tr('Forte', 'Strong'),
                          5: tr('Fortissima', 'Very strong'),
                        },
                        onSelected: (v) => setState(() => _intensity = v),
                      ),
                      label(tr('Energia', 'Energy')),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final energy in DailyEnergy.values)
                            if (energy != DailyEnergy.noData)
                              ChoicePill(
                                leading: energy.emoji,
                                label: energy.label,
                                selected: _energy == energy,
                                color: dailyBlue,
                                onTap: () => setState(() => _energy = energy),
                              ),
                        ],
                      ),
                      label(
                        tr(
                          'Concentrazione in questo momento (facoltativa)',
                          'Focus right now (optional)',
                        ),
                      ),
                      LevelScale(
                        value: _concentration,
                        color: dailyPurple,
                        labels: concentrationLabels,
                        onSelected: (v) => setState(
                          () => _concentration = _concentration == v ? null : v,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(
                          _saving
                              ? tr('Salvataggio…', 'Saving…')
                              : tr('Salva check-in', 'Save check-in'),
                        ),
                      ),
                    ],
                  ),
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Registrati oggi · ${entries.length}',
                      'Logged today · ${entries.length}',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.green,
                    ),
                  ),
                  for (final entry in entries.reversed)
                    Row(
                      children: [
                        SizedBox(
                          width: 46,
                          child: Text(
                            clock(entry.recordedAt),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        Text(
                          entry.emotion.emoji,
                          style: const TextStyle(fontSize: 17),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                entry.emotion.label,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.text,
                                ),
                              ),
                              MacChip(
                                tr(
                                  'intensità ${entry.intensity}/5',
                                  'intensity ${entry.intensity}/5',
                                ),
                              ),
                              if (entry.energy != DailyEnergy.noData)
                                MacChip(
                                  tr(
                                    'energia ${entry.energy.label.toLowerCase()}',
                                    'energy ${entry.energy.label.toLowerCase()}',
                                  ),
                                ),
                              if (entry.concentration != null)
                                MacChip(
                                  tr(
                                    'concentrazione ${entry.concentration}/5',
                                    'focus ${entry.concentration}/5',
                                  ),
                                  tone: dailyPurple,
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => widget.daily.deleteEmotion(entry.id),
                          tooltip: tr(
                            'Elimina questo check-in',
                            'Delete this check-in',
                          ),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.close,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- concentrazione

class _ConcentrationCard extends StatelessWidget {
  const _ConcentrationCard({required this.daily});
  final DailyController daily;

  @override
  Widget build(BuildContext context) {
    final day = daily.day;
    Widget block(ConcentrationKind kind) {
      final entries = day.concentration(kind);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kind.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              StatusChip(
                done: entries.isNotEmpty,
                label: entries.isEmpty
                    ? tr('Da segnare', 'To mark')
                    : entries.length == 1
                    ? tr('Segnata', 'Marked')
                    : tr('${entries.length} volte', '${entries.length} times'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LevelScale(
            value: entries.isEmpty ? null : entries.last.level,
            color: dailyPurple,
            labels: concentrationLabels,
            onSelected: (level) => daily.addConcentration(kind, level),
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in entries)
                  InputChip(
                    label: Text(
                      '${clock(entry.recordedAt)} · ${entry.level}/5',
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: dailyPurple.withValues(alpha: .1),
                    side: BorderSide.none,
                    deleteIcon: const Icon(Icons.close, size: 14),
                    deleteButtonTooltipMessage: tr('Elimina', 'Delete'),
                    // Quelle nate da un check-in emotivo si tolgono da lì.
                    onDeleted: entry.fromEmotion
                        ? null
                        : () => daily.deleteConcentration(kind, entry.id),
                  ),
              ],
            ),
          ],
        ],
      );
    }

    return DailySection(
      icon: Icons.center_focus_strong_outlined,
      color: dailyPurple,
      title: sectionLabel('Concentrazione'),
      status: StatusChip(
        done: day.dayConcentration.isNotEmpty,
        label: day.dayConcentration.isEmpty
            ? tr('Da segnare', 'To mark')
            : tr('Fatto', 'Done'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Tocca un numero ogni volta che vuoi fotografare com’è la tua attenzione.',
              'Tap a number whenever you want to capture how your attention is.',
            ),
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          block(ConcentrationKind.day),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.border),
          ),
          block(ConcentrationKind.meditation),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- movimento

class _MovementCard extends StatelessWidget {
  const _MovementCard({required this.daily});
  final DailyController daily;
  @override
  Widget build(BuildContext context) {
    final level = daily.day.movement;
    return DailySection(
      icon: Icons.graphic_eq,
      color: macOrange,
      title: sectionLabel('Movimento'),
      status: StatusChip(
        done: level != null,
        label: level == null
            ? tr('Da segnare', 'To mark')
            : tr('$level su 5', '$level of 5'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Il livello di oggi, da 1 a 5. Puoi cambiarlo quando vuoi.',
              'Today’s level, from 1 to 5. You can change it any time.',
            ),
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          LevelScale(
            value: level,
            color: macOrange,
            onSelected: daily.saveMovement,
          ),
        ],
      ),
    );
  }
}
