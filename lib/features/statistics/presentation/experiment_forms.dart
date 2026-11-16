import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../application/body_statistics_controller.dart';
import '../domain/body_statistics.dart';
import 'statistics_charts.dart';

const contextFactors = <String, String>{
  'training': 'Allenamento',
  'caffeine': 'Caffeina dopo le 14',
  'alcohol': 'Alcol',
  'illness': 'Malattia',
  'travel': 'Viaggi',
  'routine': 'Cambiamenti di routine',
};

Future<void> showExperimentForm(
  BuildContext context,
  BodyStatisticsController controller, {
  BodyExperiment? experiment,
  bool repeat = false,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ExperimentForm(
    controller: controller,
    experiment: experiment,
    repeat: repeat,
  ),
);

class _ExperimentForm extends StatefulWidget {
  const _ExperimentForm({
    required this.controller,
    this.experiment,
    this.repeat = false,
  });
  final BodyStatisticsController controller;
  final BodyExperiment? experiment;
  final bool repeat;
  @override
  State<_ExperimentForm> createState() => _ExperimentFormState();
}

class _ExperimentFormState extends State<_ExperimentForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name,
      _description,
      _objective,
      _activity,
      _minutes,
      _time,
      _notes;
  late BodyRange _range, _baseline;
  late BodyMetric _primary;
  late Set<BodyMetric> _secondary;
  late Set<int> _weekdays;
  bool _baselineEdited = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final e = widget.experiment;
    _name = TextEditingController(
      text: e == null
          ? ''
          : widget.repeat
          ? '${e.name} · ripetizione'
          : e.name,
    );
    _description = TextEditingController(text: e?.description);
    _objective = TextEditingController(text: e?.objective);
    _activity = TextEditingController(text: e?.activity);
    _minutes = TextEditingController(text: '${e?.plannedMinutes ?? 5}');
    _time = TextEditingController(text: e?.plannedTime);
    _notes = TextEditingController(text: widget.repeat ? '' : e?.notes);
    _range = e == null || widget.repeat
        ? BodyRange(
            widget.controller.today,
            widget.controller.today.add(
              Duration(days: (e?.range.days ?? 14) - 1),
            ),
          )
        : e.range;
    _baseline = e == null || widget.repeat ? _range.previous : e.baseline;
    _primary = e?.primary ?? BodyMetric.calm;
    _secondary =
        e?.secondary.toSet() ??
        {BodyMetric.sleep, BodyMetric.restingHr, BodyMetric.hrv};
    _secondary.add(BodyMetric.calm);
    _weekdays = e?.weekdays.toSet() ?? {1, 2, 3, 4, 5, 6, 7};
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _objective,
      _activity,
      _minutes,
      _time,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool baseline) async {
    final r = baseline ? _baseline : _range;
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(widget.controller.today.year + 11),
      initialDateRange: DateTimeRange(
        start: DateTime(r.start.year, r.start.month, r.start.day),
        end: DateTime(r.end.year, r.end.month, r.end.day),
      ),
      locale: const Locale('it'),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (baseline) {
        _baseline = BodyRange(result.start, result.end);
        _baselineEdited = true;
      } else {
        _range = BodyRange(result.start, result.end);
        if (!_baselineEdited) _baseline = _range.previous;
      }
    });
  }

  Future<void> _save(ExperimentStatus status) async {
    if (!_form.currentState!.validate()) return;
    final e = BodyExperiment(
      id: widget.repeat ? null : widget.experiment?.id,
      name: _name.text.trim(),
      description: _description.text.trim(),
      objective: _objective.text.trim(),
      activity: _activity.text.trim(),
      plannedMinutes: int.parse(_minutes.text),
      weekdays: _weekdays.toList()..sort(),
      plannedTime: _time.text.trim().isEmpty ? null : _time.text.trim(),
      range: _range,
      baseline: _baseline,
      primary: _primary,
      secondary: _secondary.where((m) => m != _primary).toList(),
      notes: _notes.text.trim(),
      status: status,
      repeatedFrom: widget.repeat
          ? widget.experiment?.id
          : widget.experiment?.repeatedFrom,
    );
    try {
      e.validate();
    } on ArgumentError catch (error) {
      setState(() => _error = error.message.toString());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await widget.controller.saveExperiment(e);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = widget.controller.saveError;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: usesPhoneLayout(context)
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 20)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    title: Text(
      widget.repeat
          ? 'Ripeti l’esperimento'
          : widget.experiment == null
          ? 'Nuovo esperimento'
          : 'Modifica esperimento',
    ),
    content: SizedBox(
      width: 760,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Una nuova abitudine. Un confronto nel tempo.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Nome *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Inserisci il nome' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descrizione'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _objective,
                decoration: const InputDecoration(
                  labelText: 'Obiettivo o domanda da esplorare',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 18),
              const Text(
                'Protocollo previsto',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _activity,
                decoration: const InputDecoration(
                  labelText: 'Attività da praticare',
                ),
              ),
              const SizedBox(height: 12),
              StatsGrid(
                minWidth: 230,
                children: [
                  TextFormField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Durata prevista (minuti) *',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 1440
                          ? 'Da 1 a 1440 minuti'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: _time,
                    decoration: const InputDecoration(
                      labelText: 'Orario facoltativo (HH:mm)',
                      helperText: 'Fuso Europe/Rome',
                    ),
                    validator: (v) =>
                        v == null ||
                            v.isEmpty ||
                            RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)
                        ? null
                        : 'Usa HH:mm',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 1; i <= 7; i++)
                    FilterChip(
                      label: Text(
                        const [
                          'Lun',
                          'Mar',
                          'Mer',
                          'Gio',
                          'Ven',
                          'Sab',
                          'Dom',
                        ][i - 1],
                      ),
                      selected: _weekdays.contains(i),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _weekdays.add(i);
                        } else {
                          _weekdays.remove(i);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _pick(false),
                icon: const Icon(Icons.date_range),
                label: Text('Durante · ${rangeLabel(_range)}'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _pick(true),
                icon: const Icon(Icons.history),
                label: Text('Prima · ${rangeLabel(_baseline)}'),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<BodyMetric>(
                isExpanded: true,
                initialValue: _primary,
                decoration: const InputDecoration(
                  labelText: 'Metrica principale',
                ),
                items: [
                  for (final m in BodyMetric.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) => setState(() => _primary = m!),
              ),
              const SizedBox(height: 14),
              const Text('Metriche secondarie'),
              Wrap(
                spacing: 6,
                children: [
                  for (final m in BodyMetric.values.where((m) => m != _primary))
                    FilterChip(
                      label: Text(m.label),
                      selected: m == BodyMetric.calm || _secondary.contains(m),
                      onSelected: m == BodyMetric.calm
                          ? null
                          : (v) => setState(() {
                              if (v) {
                                _secondary.add(m);
                              } else {
                                _secondary.remove(m);
                              }
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'La calma dal diario personale (1–5) è sempre inclusa nel confronto.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Note iniziali'),
                maxLines: 3,
              ),
              if (widget.repeat)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'La ripetizione mantiene il collegamento al test precedente e parte senza registrazioni.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      if (widget.experiment == null ||
          widget.repeat ||
          widget.experiment?.status == ExperimentStatus.draft)
        OutlinedButton(
          onPressed: _busy ? null : () => _save(ExperimentStatus.draft),
          child: const Text('Salva bozza'),
        ),
      FilledButton(
        onPressed: _busy
            ? null
            : () => _save(
                widget.repeat ||
                        widget.experiment == null ||
                        widget.experiment?.status == ExperimentStatus.draft
                    ? ExperimentStatus.running
                    : widget.experiment!.status,
              ),
        child: Text(
          _busy
              ? 'Salvataggio…'
              : widget.experiment == null ||
                    widget.repeat ||
                    widget.experiment?.status == ExperimentStatus.draft
              ? 'Avvia esperimento'
              : 'Salva modifiche',
        ),
      ),
    ],
  );
}

Future<void> showLogForm(
  BuildContext context,
  BodyStatisticsController controller, {
  ExperimentLog? log,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _LogForm(controller: controller, log: log),
);

class _LogForm extends StatefulWidget {
  const _LogForm({required this.controller, this.log});
  final BodyStatisticsController controller;
  final ExperimentLog? log;
  @override
  State<_LogForm> createState() => _LogFormState();
}

class _LogFormState extends State<_LogForm> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  String? _status;
  late final TextEditingController _minutes, _time, _stress, _notes;
  double? _legacyCalm;
  late Map<String, bool?> _context;
  bool _busy = false;
  String? _error;
  BodyExperiment get e => widget.controller.selected!;
  bool get _baseline => e.baseline.contains(_date);
  @override
  void initState() {
    super.initState();
    final l = widget.log;
    _date =
        l?.date ??
        (widget.controller.today.isBefore(e.range.start)
            ? (widget.controller.today.isAfter(e.baseline.end)
                  ? e.baseline.end
                  : widget.controller.today)
            : widget.controller.today.isAfter(e.range.end)
            ? e.range.end
            : widget.controller.today);
    _assign(l ?? widget.controller.analysis?.logAt(_date));
  }

  void _assign(ExperimentLog? l) {
    _status = l?.sessionStatus;
    _minutes = TextEditingController(text: l?.minutes?.toString() ?? '');
    _time = TextEditingController(text: l?.time?.substring(0, 5) ?? '');
    _legacyCalm = l?.calm;
    _stress = TextEditingController(text: l?.stress?.toString() ?? '');
    _notes = TextEditingController(text: l?.notes ?? '');
    _context = {...?l?.context};
  }

  @override
  void dispose() {
    for (final c in [_minutes, _time, _stress, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _rating(String? v) {
    if (v == null || v.isEmpty) return null;
    final n = double.tryParse(v.replaceAll(',', '.'));
    return n == null || !n.isFinite || n < 0 || n > 10
        ? 'Valore da 0 a 10'
        : null;
  }

  Future<void> _pick() async {
    final date = await showDatePicker(
      context: context,
      firstDate: e.baseline.start,
      lastDate: widget.controller.today.isBefore(e.range.end)
          ? widget.controller.today
          : e.range.end,
      initialDate: _date,
      selectableDayPredicate: (d) =>
          e.baseline.contains(statsDate(d)) || e.range.contains(statsDate(d)),
      locale: const Locale('it'),
    );
    if (date == null || !mounted) return;
    final existing = widget.controller.analysis!.logAt(statsDate(date));
    setState(() {
      _date = statsDate(date);
      _status = existing?.sessionStatus;
      _minutes.text = existing?.minutes?.toString() ?? '';
      _time.text = existing?.time?.substring(0, 5) ?? '';
      _legacyCalm = existing?.calm;
      _stress.text = existing?.stress?.toString() ?? '';
      _notes.text = existing?.notes ?? '';
      _context = {...?existing?.context};
    });
  }

  Future<void> _save({bool delete = false}) async {
    if (!delete && !_form.currentState!.validate()) return;
    final l = ExperimentLog(
      experimentId: e.id!,
      date: _date,
      sessionStatus: _baseline ? null : _status,
      minutes: _baseline ? null : int.tryParse(_minutes.text),
      time: _baseline || _time.text.isEmpty ? null : _time.text,
      calm: _legacyCalm,
      stress: double.tryParse(_stress.text.replaceAll(',', '.')),
      notes: _notes.text.trim(),
      context: _context,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    final success = await widget.controller.saveLog(l, delete: delete);
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = widget.controller.saveError;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: usesPhoneLayout(context)
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 20)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    title: const Text('Diario dell’esperimento'),
    content: SizedBox(
      width: 660,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Registrazione manuale · I campi vuoti rimangono non registrati.',
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  '${_baseline ? 'Prima' : 'Durante'} · ${shortStatsDate(_date)} ${_date.year}',
                ),
              ),
              const SizedBox(height: 14),
              if (!_baseline) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('status-$_date-$_status'),
                  initialValue: _status ?? 'unknown',
                  decoration: const InputDecoration(labelText: 'Pratica'),
                  items: const [
                    DropdownMenuItem(
                      value: 'unknown',
                      child: Text('Non registrata'),
                    ),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completata'),
                    ),
                    DropdownMenuItem(value: 'partial', child: Text('Parziale')),
                    DropdownMenuItem(value: 'skipped', child: Text('Saltata')),
                  ],
                  onChanged: (v) =>
                      setState(() => _status = v == 'unknown' ? null : v),
                ),
                const SizedBox(height: 12),
                StatsGrid(
                  minWidth: 210,
                  children: [
                    TextFormField(
                      controller: _minutes,
                      decoration: const InputDecoration(
                        labelText: 'Durata effettiva (minuti)',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final n = int.tryParse(v);
                        return n == null || n < 0 || n > 1440
                            ? 'Da 0 a 1440 minuti'
                            : null;
                      },
                    ),
                    TextFormField(
                      controller: _time,
                      decoration: const InputDecoration(
                        labelText: 'Orario (HH:mm) · Europe/Rome',
                      ),
                      validator: (v) =>
                          v == null ||
                              v.isEmpty ||
                              RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)
                          ? null
                          : 'Usa HH:mm',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              StatsGrid(
                minWidth: 210,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Calma dal diario · 1–5',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        BodyMetric.calm.format(
                          widget.controller.analysis?.calmByDate[statsKey(
                            _date,
                          )],
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          color: AppColors.green,
                        ),
                      ),
                      const Text(
                        'Media delle emozioni “Calmo” registrate nel diario personale.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _stress,
                    decoration: const InputDecoration(
                      labelText: 'Stress percepito · 0–10',
                    ),
                    keyboardType: TextInputType.number,
                    validator: _rating,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Fattori di contesto',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              StatsGrid(
                minWidth: 210,
                children: [
                  for (final f in contextFactors.entries)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey('${f.key}-$_date-${_context[f.key]}'),
                      initialValue: _context[f.key]?.toString() ?? 'unknown',
                      decoration: InputDecoration(labelText: f.value),
                      items: const [
                        DropdownMenuItem(
                          value: 'unknown',
                          child: Text('Non registrato'),
                        ),
                        DropdownMenuItem(value: 'true', child: Text('Sì')),
                        DropdownMenuItem(value: 'false', child: Text('No')),
                      ],
                      onChanged: (v) => setState(
                        () => _context[f.key] = v == 'unknown'
                            ? null
                            : v == 'true',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Note della giornata',
                ),
                maxLines: 3,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      if (widget.controller.analysis?.logAt(_date) != null)
        TextButton(
          onPressed: _busy ? null : () => _save(delete: true),
          child: const Text('Elimina registrazione'),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: _busy ? null : () => _save(),
        child: Text(_busy ? 'Salvataggio…' : 'Salva giornata'),
      ),
    ],
  );
}
