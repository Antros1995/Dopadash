
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/presentation/mac_widgets.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../dashboard/presentation/widgets/routine_tile.dart' show routineIcon;
import '../../fitbit/application/fitbit_controller.dart';
import '../../routines/application/routine_controller.dart';
import '../../routines/domain/routine.dart';
import '../application/daily_controller.dart';
import '../domain/daily_models.dart';
import 'daily_widgets.dart';
import 'trend_chart.dart';
import '../../wardrobe/wardrobe_repository.dart' show ProgressPhotoRepository;
import 'progress_photos_card.dart';

/// Sport: l'allenamento e l'alimentazione del giorno, l'attività misurata
/// dall'orologio e, in fondo, peso e misure del corpo.
class SportPage extends StatefulWidget {
  const SportPage({
    required this.routines,
    required this.daily,
    required this.fitbit,
    required this.onSelectDate,
    this.photos,
    super.key,
  });

  /// Le foto dei progressi; se manca la sezione non compare.
  final ProgressPhotoRepository? photos;
  final RoutineController routines;
  final DailyController daily;
  final FitbitController fitbit;
  final ValueChanged<DateTime> onSelectDate;

  @override
  State<SportPage> createState() => SportPageState();
}

class SportPageState extends State<SportPage> {
  final _scroll = ScrollController();
  final _keys = {
    for (final s in const ['Allenamento', 'Attività', 'Peso e misure', 'Foto'])
      s: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    if (!widget.daily.measurementsLoaded) widget.daily.loadMeasurements();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void showSection(String section) {
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

  static const _sportIcons = {'gym', 'walking', 'food'};

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.routines,
      widget.daily,
      widget.fitbit,
    ]),
    builder: (context, _) {
      final daily = widget.daily, routines = widget.routines;
      final sport = [
        for (final r in routines.routines)
          if (_sportIcons.contains(r.iconKey)) r,
      ];
      final marked = sport.where((r) => routines.entryFor(r.id).isMarked).length;
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
                  title: 'Sport',
                  subtitle:
                      '${weekdayDate(daily.date)} · allenamento, alimentazione e misure',
                  date: daily.date,
                  today: daily.today,
                  onSelectDate: widget.onSelectDate,
                ),
                if (daily.error != null || routines.syncError != null)
                  DailyErrorBanner(
                    onRetry: () {
                      daily.refresh();
                      if (routines.syncError != null) routines.retrySave();
                    },
                  ),
                const SizedBox(height: 16),
                KeyedSubtree(
                  key: _keys['Allenamento'],
                  child: DailySection(
                    icon: Icons.fitness_center,
                    color: macOrange,
                    title: 'Allenamento e alimentazione',
                    status: StatusChip(
                      done: sport.isNotEmpty && marked == sport.length,
                      label: sport.isEmpty
                          ? 'Nessuna abitudine'
                          : '$marked di ${sport.length} segnate',
                    ),
                    child: sport.isEmpty
                        ? const Text(
                            'Qui compaiono le abitudini Palestra, Camminata e Alimentazione quando sono attive nella Quotidianità.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < sport.length; i++) ...[
                                if (i > 0)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Divider(
                                      height: 1,
                                      color: AppColors.border,
                                    ),
                                  ),
                                _SportHabit(
                                  routine: sport[i],
                                  entry: routines.entryFor(sport[i].id),
                                  onStatus: (s) =>
                                      routines.setStatus(sport[i].id, s),
                                  onDetail: (o) =>
                                      routines.setDetail(sport[i].id, o),
                                  onEditOptions: () async {
                                    final result =
                                        await showDialog<
                                          List<RoutineDetailOption>
                                        >(
                                          context: context,
                                          builder: (_) => _OptionsDialog(
                                            routine: sport[i],
                                          ),
                                        );
                                    if (result != null) {
                                      await routines.updateDetailOptions(
                                        sport[i].id,
                                        result,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _keys['Attività'],
                  child: _ActivityCard(fitbit: widget.fitbit),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _keys['Peso e misure'],
                  child: _BodyCard(daily: daily),
                ),
                if (widget.photos != null) ...[
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: _keys['Foto'],
                    child: ProgressPhotosCard(
                      repository: widget.photos!,
                      today: daily.today,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Un'abitudine sportiva con due risposte grandi e, se serve, il dettaglio.
class _SportHabit extends StatelessWidget {
  const _SportHabit({
    required this.routine,
    required this.entry,
    required this.onStatus,
    required this.onDetail,
    required this.onEditOptions,
  });
  final VoidCallback onEditOptions;
  final RoutineDefinition routine;
  final RoutineEntry entry;
  final ValueChanged<RoutineStatus> onStatus;
  final ValueChanged<RoutineDetailOption?> onDetail;

  @override
  Widget build(BuildContext context) {
    final status = entry.status, isFood = routine.iconKey == 'food';
    final isGym = routine.iconKey == 'gym';
    // In palestra, oltre alle schede, si può segnare un altro allenamento.
    final options = routine.detailOptions;
    final showOptions =
        (options.isNotEmpty || isGym) &&
        (isFood ? status == RoutineStatus.ko : status == RoutineStatus.ok);
    void toggle(RoutineStatus target) =>
        onStatus(status == target ? RoutineStatus.unmarked : target);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(routineIcon(routine.iconKey), size: 20, color: AppColors.text),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                routine.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            if (status == RoutineStatus.ok &&
                entry.completionTimeMinutes != null)
              MacChip(
                formatMinutes(entry.completionTimeMinutes!),
                tone: AppColors.green,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoicePill(
              leading: '✓',
              label: isFood ? 'Rispettata' : 'Fatto',
              selected: status == RoutineStatus.ok,
              onTap: () => toggle(RoutineStatus.ok),
            ),
            ChoicePill(
              leading: '✕',
              label: isFood ? 'Sgarro' : 'Saltato',
              selected: status == RoutineStatus.ko,
              color: AppColors.danger,
              onTap: () => toggle(RoutineStatus.ko),
            ),
          ],
        ),
        if (showOptions) ...[
          const SizedBox(height: 10),
          Text(
            isFood
                ? 'Quanto è stato lo sgarro?'
                : isGym
                ? 'Che allenamento hai fatto?'
                : 'Quale?',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                ChoicePill(
                  label: option.label,
                  selected: entry.selectedDetailOptionId == option.id,
                  color: isFood ? AppColors.danger : macOrange,
                  onTap: () => onDetail(
                    entry.selectedDetailOptionId == option.id ? null : option,
                  ),
                ),
              if (isGym)
                TextButton.icon(
                  onPressed: onEditOptions,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Modifica allenamenti'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    minimumSize: const Size(0, 32),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.fitbit});
  final FitbitController fitbit;

  @override
  Widget build(BuildContext context) {
    final day = fitbit.day;
    String thousands(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    );
    return DailySection(
      icon: Icons.watch_outlined,
      color: dailyBlue,
      title: 'Attività misurata',
      status: StatusChip(
        done: day != null,
        label: day == null ? 'Nessun dato' : 'Dall’orologio',
      ),
      child: day == null
          ? const Text(
              'Per questo giorno non ci sono dati dell’orologio.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          : LayoutBuilder(
              builder: (context, box) {
                final columns = box.maxWidth >= 620 ? 4 : 2;
                final width = (box.maxWidth - (columns - 1) * 10) / columns;
                final tiles = <(String, String, String, Color)>[
                  ('Passi', thousands(day.steps), '', AppColors.green),
                  (
                    'Distanza',
                    day.distanceKm.toStringAsFixed(1).replaceAll('.', ','),
                    'km',
                    dailyBlue,
                  ),
                  ('Calorie', thousands(day.calories), 'kcal', macOrange),
                  ('Minuti attivi', '${day.activeMinutes}', 'min', dailyPurple),
                ];
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final tile in tiles)
                      SizedBox(
                        width: width,
                        child: StatTile(
                          label: tile.$1,
                          value: tile.$2,
                          unit: tile.$3,
                          color: tile.$4,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.footer,
  });
  final String label, value, unit;
  final Color color;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            text: value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
              color: AppColors.text,
            ),
            children: [
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        if (footer != null) ...[const SizedBox(height: 4), footer!],
      ],
    ),
  );
}

// ------------------------------------------------------------ peso e misure

class _BodyCard extends StatefulWidget {
  const _BodyCard({required this.daily});
  final DailyController daily;
  @override
  State<_BodyCard> createState() => _BodyCardState();
}

class _BodyCardState extends State<_BodyCard> {
  BodyMetric _metric = BodyMetric.weight;

  /// Mesi mostrati nel grafico; 0 = tutto lo storico.
  int _months = 12;

  static String number(double v) => v
      .toStringAsFixed(1)
      .replaceAll(RegExp(r'\.0$'), '')
      .replaceAll('.', ',');
  static String shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';

  Future<void> _edit([BodyMeasurement? existing]) async {
    final result = await showDialog<BodyMeasurement>(
      context: context,
      builder: (_) => _MeasurementDialog(
        initial: existing,
        date: existing?.date ?? widget.daily.today,
        all: widget.daily.measurements,
      ),
    );
    if (result != null) await widget.daily.saveMeasurement(result);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.daily.measurements;
    (BodyMeasurement, BodyMeasurement?)? latest(BodyMetric metric) {
      final with_ = [
        for (final m in all)
          if (m[metric] != null) m,
      ];
      if (with_.isEmpty) return null;
      return (with_.last, with_.length > 1 ? with_[with_.length - 2] : null);
    }

    final history = [
      for (final m in all)
        if (m[_metric] != null) (m.date, m[_metric]!),
    ];
    final today = widget.daily.today;
    final from = _months == 0
        ? null
        : DateTime(today.year, today.month - _months, today.day);
    final inRange = [
      for (final p in history)
        if (from == null || !p.$1.isBefore(from)) p,
    ];
    // Se nel periodo scelto c'è meno di due misure si mostra tutto lo storico.
    final series = inRange.length >= 2 ? inRange : history;
    final last = all.isEmpty ? null : all.last;
    return DailySection(
      icon: Icons.monitor_weight_outlined,
      color: AppColors.green,
      title: 'Peso e misure',
      status: StatusChip(
        done: last != null,
        label: last == null
            ? 'Nessuna misura'
            : 'Ultima il ${shortDate(last.date)}',
      ),
      action: FilledButton.icon(
        onPressed: _edit,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Nuova misura'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      child: !widget.daily.measurementsLoaded
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          : all.isEmpty
          ? const Text(
              'Nessuna misura ancora. Premi “Nuova misura”: basta anche solo il peso.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final columns = box.maxWidth >= 820
                        ? 6
                        : box.maxWidth >= 520
                        ? 3
                        : 2;
                    final width =
                        (box.maxWidth - (columns - 1) * 10) / columns;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final metric in BodyMetric.values)
                          SizedBox(
                            width: width,
                            child: InkWell(
                              onTap: () => setState(() => _metric = metric),
                              borderRadius: BorderRadius.circular(10),
                              child: Builder(
                                builder: (context) {
                                  final pair = latest(metric);
                                  final value = pair?.$1[metric];
                                  final before = pair?.$2?[metric];
                                  final delta = value != null && before != null
                                      ? value - before
                                      : null;
                                  return StatTile(
                                    label: metric.label,
                                    value: value == null ? '—' : number(value),
                                    unit: value == null ? '' : metric.unit,
                                    color: metric == _metric
                                        ? AppColors.green
                                        : AppColors.textMuted,
                                    footer: Text(
                                      delta == null
                                          ? (value == null
                                                ? 'mai misurato'
                                                : 'prima misura')
                                          : delta.abs() < .05
                                          ? 'invariato'
                                          : '${delta > 0 ? '▲ +' : '▼ −'}${number(delta.abs())} ${metric.unit}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${_metric.label} nel tempo',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    MacSegmented<int>(
                      values: const [3, 12, 0],
                      selected: _months,
                      labelFor: (m) => m == 0
                          ? 'Tutto'
                          : m == 12
                          ? '1 anno'
                          : '$m mesi',
                      onSelected: (m) => setState(() => _months = m),
                    ),
                    if (series.length >= 2)
                      MacChip(
                        '${series.last.$2 - series.first.$2 > 0 ? '▲ +' : '▼ −'}${number((series.last.$2 - series.first.$2).abs())} ${_metric.unit} nel periodo',
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                TrendChart(points: series, unit: _metric.unit),
                if (series.length == 1)
                  const Text(
                    'C’è una sola misura: alla prossima vedrai la linea.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                const SizedBox(height: 14),
                const Text(
                  'Ultime misure',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                for (final m in all.reversed.take(6)) ...[
                  Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(
                          shortDate(m.date),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final metric in BodyMetric.values)
                              if (m[metric] != null)
                                MacChip(
                                  '${metric.label} ${number(m[metric]!)} ${metric.unit}',
                                ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _edit(m),
                        tooltip: 'Modifica questa misura',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const MacDivider(indent: 70),
                ],
              ],
            ),
    );
  }
}

/// Rinomina, aggiunge o toglie gli allenamenti tra cui scegliere.
class _OptionsDialog extends StatefulWidget {
  const _OptionsDialog({required this.routine});
  final RoutineDefinition routine;
  @override
  State<_OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<_OptionsDialog> {
  late final _rows = [
    for (final o in widget.routine.detailOptions)
      (o, TextEditingController(text: o.label)),
  ];
  final _new = TextEditingController();

  @override
  void dispose() {
    for (final r in _rows) {
      r.$2.dispose();
    }
    _new.dispose();
    super.dispose();
  }

  void _add([String? name]) {
    final label = (name ?? _new.text).trim();
    if (label.isEmpty) return;
    setState(() {
      _rows.add((
        RoutineDetailOption(
          id: 'opzione_${DateTime.now().microsecondsSinceEpoch}',
          label: label,
          position: _rows.length,
        ),
        TextEditingController(text: label),
      ));
      _new.clear();
    });
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: AppColors.fill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final names = _rows.map((r) => r.$2.text.trim().toLowerCase()).toSet();
    return AlertDialog(
      title: Text('Allenamenti di ${widget.routine.name}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Rinomina, togli o aggiungi. Vale da oggi in poi: i giorni passati tengono i nomi di allora.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              for (final row in _rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: row.$2,
                          maxLength: 60,
                          onChanged: (_) => setState(() {}),
                          decoration: _decoration('Nome').copyWith(
                            counterText: '',
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _rows.remove(row);
                          row.$2.dispose();
                        }),
                        tooltip: 'Togli',
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          size: 20,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _new,
                      maxLength: 60,
                      onSubmitted: (_) => _add(),
                      decoration: _decoration(
                        'Nuovo allenamento…',
                      ).copyWith(counterText: ''),
                    ),
                  ),
                  IconButton(
                    onPressed: _add,
                    tooltip: 'Aggiungi',
                    icon: const Icon(Icons.add_circle, color: AppColors.green),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final idea in const [
                    'Forza',
                    'Cardio',
                    'Corsa',
                    'Yoga',
                    'Nuoto',
                  ])
                    if (!names.contains(idea.toLowerCase()))
                      ActionChip(
                        label: Text('+ $idea'),
                        onPressed: () => _add(idea),
                        visualDensity: VisualDensity.compact,
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, [
            for (var i = 0; i < _rows.length; i++)
              if (_rows[i].$2.text.trim().isNotEmpty)
                RoutineDetailOption(
                  id: _rows[i].$1.id,
                  label: _rows[i].$2.text.trim(),
                  position: i,
                  score: _rows[i].$1.score,
                ),
          ]),
          child: const Text('Salva'),
        ),
      ],
    );
  }
}

class _MeasurementDialog extends StatefulWidget {
  const _MeasurementDialog({
    required this.initial,
    required this.date,
    required this.all,
  });
  final BodyMeasurement? initial;
  final DateTime date;
  final List<BodyMeasurement> all;
  @override
  State<_MeasurementDialog> createState() => _MeasurementDialogState();
}

class _MeasurementDialogState extends State<_MeasurementDialog> {
  late DateTime _date = widget.date;
  late final _fields = {
    for (final metric in BodyMetric.values) metric: TextEditingController(),
  };
  String? _error;

  @override
  void initState() {
    super.initState();
    _fill(widget.initial ?? _existing(_date));
  }

  BodyMeasurement? _existing(DateTime date) =>
      widget.all.where((m) => DateUtils.isSameDay(m.date, date)).firstOrNull;

  void _fill(BodyMeasurement? m) {
    for (final metric in BodyMetric.values) {
      final v = m?[metric];
      _fields[metric]!.text = v == null
          ? ''
          : v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '').replaceAll('.', ',');
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final values = <BodyMetric, double>{};
    for (final metric in BodyMetric.values) {
      final raw = _fields[metric]!.text.trim().replaceAll(',', '.');
      if (raw.isEmpty) continue;
      final value = double.tryParse(raw);
      if (value == null || value <= 0 || value > 999) {
        setState(() => _error = '${metric.label}: scrivi un numero, per esempio 78,5.');
        return;
      }
      values[metric] = value;
    }
    if (values.isEmpty) {
      setState(() => _error = 'Scrivi almeno un valore: basta il peso.');
      return;
    }
    Navigator.pop(context, BodyMeasurement(date: _date, values: values));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Misura del corpo'),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.initial != null
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            _date = picked;
                            _fill(_existing(picked));
                          });
                        }
                      },
                icon: const Icon(Icons.event_outlined, size: 17),
                label: Text(
                  '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                ),
              ),
            ),
            const Text(
              'Compila solo quello che hai misurato.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            for (final metric in BodyMetric.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        metric.label,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _fields[metric],
                        autofocus: metric == BodyMetric.weight,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.fill,
                          suffixText: metric.unit,
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
                  ],
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(onPressed: _save, child: const Text('Salva')),
    ],
  );
}
