import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../../core/utils/date_formatters.dart';
import '../../data_export/data/export_file_saver.dart';
import '../../fitbit/application/fitbit_controller.dart';
import '../application/body_statistics_controller.dart';
import '../data/compare_sources.dart';
import '../domain/body_statistics.dart';
import '../domain/heart_rate_statistics.dart';
import 'compare_panel.dart';
import 'experiment_forms.dart';
import 'perception_view.dart';
import 'statistics_charts.dart';

const bodySections = <(String, IconData)>[
  ('Panoramica', Icons.grid_view_outlined),
  ('Sonno', Icons.bedtime_outlined),
  ('Cuore e recupero', Icons.favorite_border),
  ('Attività', Icons.directions_run),
  ('Percezione', Icons.sentiment_satisfied_alt),
  ('Abitudini', Icons.checklist_rounded),
  ('Cellulare', Icons.smartphone),
  ('Sport', Icons.fitness_center),
  ('Esperimenti', Icons.science_outlined),
];

/// Riepiloghi che non vengono dall'orologio: hanno un loro periodo e non
/// usano gli strumenti dei dati Fitbit.
const _recapSections = {'Abitudini', 'Cellulare', 'Sport'};

class BodyStatisticsPage extends StatefulWidget {
  const BodyStatisticsPage({
    required this.controller,
    required this.fitbit,
    this.recapBuilder,
    this.compareSources,
    super.key,
  });
  final BodyStatisticsController controller;
  final FitbitController fitbit;

  /// Costruisce il riepilogo di Abitudini, Cellulare o Sport.
  final Widget Function(String section)? recapBuilder;

  /// Dati non Fitbit per il confronto tra parametri della Panoramica.
  final CompareSources? compareSources;
  @override
  State<BodyStatisticsPage> createState() => _BodyStatisticsPageState();
}

class _BodyStatisticsPageState extends State<BodyStatisticsPage> {
  final _scroll = ScrollController();
  bool _compareOpen = false;
  BodyStatisticsController get c => widget.controller;
  bool get _recap => _recapSections.contains(c.section);
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await c.load();
    if (mounted && c.error == null && c.section != 'Percezione') {
      await c.refresh();
    }
  }

  Future<void> _refreshCurrentData() async {
    if (c.section == 'Percezione') {
      await c.loadPerceptions();
    } else {
      await c.refresh();
      if (mounted && c.section == 'Esperimenti') await c.loadPerceptions();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    try {
      final experiment = c.selected;
      final analysis = c.analysis;
      final data = <String, Object?>{
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'timezone': 'Europe/Rome',
        'preferences': c.preferences,
        if (c.section == 'Percezione' || c.section == 'Esperimenti')
          'emotion_entries': c.perceptions
              .where(
                (entry) =>
                    !entry.date.isAfter(c.today) &&
                    (c.section == 'Esperimenti' && experiment != null
                        ? experiment.baseline.contains(entry.date) ||
                              experiment.range.contains(entry.date)
                        : c.range.contains(entry.date) ||
                              (c.comparisonRange?.contains(entry.date) ??
                                  false)),
              )
              .map((entry) => entry.toJson())
              .toList(),
        if (experiment != null && c.section == 'Esperimenti') ...{
          'experiment': experiment.toJson(),
          'manual_logs': c.logs.map((l) => l.toJson()).toList(),
          'comparison': [
            for (final metric in experiment.metrics)
              {
                'metric': metric.key,
                'unit': metric.unit,
                'before': _summaryJson(
                  analysis!.summary(experiment.baseline, metric),
                ),
                'during': _summaryJson(
                  analysis.summary(experiment.range, metric),
                ),
                'excluded_before': analysis.excludedCount(experiment.baseline),
                'excluded_during': analysis.excludedCount(experiment.range),
              },
          ],
          'interpretation': 'Confronto descrittivo, non causale',
        },
        'fitbit_days': c.days
            .where(
              (d) => c.section == 'Esperimenti' && experiment != null
                  ? experiment.baseline.contains(d.date) ||
                        experiment.range.contains(d.date)
                  : c.range.contains(d.date) ||
                        (c.comparisonRange?.contains(d.date) ?? false),
            )
            .map((d) => d.data)
            .toList(),
      };
      final path = await saveExportFile(
        Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
        ),
        'statistiche_${statsKey(c.today)}_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Esportazione salvata: $path')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esportazione non riuscita. Riprova.')),
        );
      }
    }
  }

  Map<String, Object?> _summaryJson(BodySummary s) => {
    'mean': s.mean,
    'total': s.total,
    'standard_deviation': s.sd,
    'observations': s.count,
    'expected_days': s.expected,
    'coverage': s.coverage,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, widget.fitbit]),
    builder: (context, _) => Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: pageInsets(context, const EdgeInsets.fromLTRB(16, 12, 18, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            // Le schede stanno subito sotto l'intestazione, così restano ferme
            // anche quando la barra del periodo non c'è (Esperimenti).
            const SizedBox(height: 10),
            _tabs(),
            const SizedBox(height: 8),
            if (c.section != 'Esperimenti' && !_recap) ...[
              _timeControls(),
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 4),
            if (c.loaded &&
                c.section != 'Percezione' &&
                !_recap &&
                !usesPhoneLayout(context))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: c.recovering || c.syncing
                          ? null
                          : c.recoverMissingDays,
                      icon: const Icon(Icons.cloud_download_outlined, size: 16),
                      label: Text(
                        c.recovering
                            ? 'Recupero ${c.recoveredDays} / ${c.recoveryTotal} giorni…'
                            : 'Recupera giorni mancanti dai periodi',
                      ),
                    ),
                    if (c.recovering)
                      TextButton(
                        onPressed: c.cancelRecovery,
                        child: const Text('Interrompi dopo questo giorno'),
                      ),
                    const Text(
                      'I giorni già salvati restano disponibili. Le date senza misurazioni rimangono vuote.',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            if (c.section != 'Percezione' &&
                !_recap &&
                c.days.any((d) => c.range.contains(d.date) && !d.finalized))
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Il periodo include giornate ancora in aggiornamento: i riepiloghi sono provvisori.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            if (c.saveError != null)
              _notice(
                c.saveError!,
                action: () => c.persist(),
                label: 'Riprova salvataggio',
              ),
            if (c.syncError != null)
              _notice(
                '${c.syncError!} Lo storico già salvato resta consultabile.',
                action: c.refresh,
              ),
            if (c.error != null) _notice(c.error!, action: c.load),
            if ((c.section == 'Percezione' || c.section == 'Esperimenti') &&
                c.perceptionError != null)
              _notice(
                'Emozioni: ${c.perceptionError!}',
                action: c.loadPerceptions,
              ),
            if (!c.loading &&
                c.perceptionsLoading &&
                (c.section == 'Percezione' || c.section == 'Esperimenti'))
              const LinearProgressIndicator(),
            if (_recap)
              widget.recapBuilder?.call(c.section) ??
                  const Text('Riepilogo non disponibile.')
            else if (c.loading)
              const SizedBox(
                height: 350,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (c.loaded)
              ...switch (c.section) {
                'Sonno' => _sleep(),
                'Cuore e recupero' => _heart(),
                'Attività' => _activity(),
                'Percezione' => [PerceptionView(controller: c)],
                'Esperimenti' => _experiments(),
                _ => _overview(),
              },
            const SizedBox(height: 10),
            if (usesPhoneLayout(context) &&
                c.loaded &&
                !_recap &&
                c.section != 'Percezione')
              _phoneDataTools(),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                Text(
                  _recap
                      ? 'Dati della Quotidianità e dello Sport · gli stessi dell’app per iPhone'
                      : c.section == 'Percezione'
                      ? 'Diario personale · Emozioni · scala 1–5 · Europe/Rome'
                      : 'Fitbit · Europe/Rome · notti attribuite al giorno del risveglio${c.range.days == 1 ? ' · dati notturni e riepiloghi giornalieri, nessun campione orario ricostruito' : ''}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
                TextButton.icon(
                  onPressed: c.loaded ? _export : null,
                  icon: const Icon(Icons.download_outlined, size: 15),
                  label: const Text(
                    'Esporta dati e confronto',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _notice(
    String message, {
    VoidCallback? action,
    String label = 'Riprova',
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: StatsPanel(
      tint: AppColors.warningSoft,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
          if (action != null) TextButton(onPressed: action, child: Text(label)),
        ],
      ),
    ),
  );

  Widget _phoneHeader() {
    final title = switch (c.section) {
      'Panoramica' => 'Il tuo corpo, nel tempo.',
      'Esperimenti' => 'Esperimenti personali',
      _ => c.section,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        image: DecorationImage(
          image: const AssetImage('assets/images/alpine-header.png'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.white.withValues(alpha: .88),
            BlendMode.srcOver,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  capitalize(formatItalianDate(c.today)),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: c.section == 'Percezione'
                    ? 'Aggiorna le emozioni dal diario'
                    : 'Sincronizza lo storico Fitbit',
                onPressed: c.loaded && !c.syncing && !c.perceptionsLoading
                    ? _refreshCurrentData
                    : null,
                icon: c.syncing || c.perceptionsLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 22),
              ),
            ],
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 25,
              height: 1.15,
              letterSpacing: -.5,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            c.section == 'Percezione'
                ? 'Diario personale · ${c.perceptions.length} registrazioni'
                : '${widget.fitbit.isConnected ? 'Fitbit connesso' : 'Archivio Fitbit'} · ${c.days.length} giorni salvati',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _phoneTimeControls() => StatsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<BodyPeriod>(
                key: ValueKey('phone-period-${c.period}'),
                initialValue: c.period,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Periodo',
                  isDense: true,
                ),
                items: [
                  for (final p in BodyPeriod.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (p) async {
                  if (p == null) return;
                  if (p == BodyPeriod.custom) {
                    final r = await _pickRange(c.range);
                    if (r != null) {
                      c.change(() {
                        c.period = p;
                        c.customRange = r;
                      });
                    }
                  } else {
                    c.change(() => c.period = p);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Filtri e confronto',
              onPressed: _phoneFilters,
              icon: const Icon(Icons.tune, color: AppColors.green),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              tooltip: 'Periodo precedente',
              onPressed: c.period == BodyPeriod.all ? null : () => _shift(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  final r = await _pickRange(c.range);
                  if (r != null) {
                    c.change(() {
                      c.period = BodyPeriod.custom;
                      c.customRange = r;
                    });
                  }
                },
                child: Text(
                  rangeLabel(c.range),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Periodo successivo',
              onPressed:
                  c.period == BodyPeriod.all || !c.range.end.isBefore(c.today)
                  ? null
                  : () => _shift(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Text(
          '${c.compare ? 'Confronto attivo' : 'Senza confronto'}${c.moving ? ' · Media mobile 7 giorni' : ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    ),
  );

  void _phoneFilters() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: c,
      builder: (context, _) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Filtri e confronto',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'phone-comparison-${c.compare}-${c.customComparison}',
                ),
                initialValue: !c.compare
                    ? 'none'
                    : c.customComparison == null
                    ? 'previous'
                    : 'custom',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Confronta con'),
                items: const [
                  DropdownMenuItem(
                    value: 'previous',
                    child: Text('Periodo precedente'),
                  ),
                  DropdownMenuItem(
                    value: 'custom',
                    child: Text('Intervallo personalizzato'),
                  ),
                  DropdownMenuItem(
                    value: 'none',
                    child: Text('Nessun confronto'),
                  ),
                ],
                onChanged: (v) async {
                  if (v == 'custom') {
                    final r = await _pickRange(
                      c.comparisonRange ?? c.range.previous,
                    );
                    if (r != null) {
                      c.change(() {
                        c.compare = true;
                        c.customComparison = r;
                      });
                    }
                  } else {
                    c.change(() {
                      c.compare = v != 'none';
                      c.customComparison = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Media mobile 7 giorni'),
                value: c.moving,
                onChanged: (v) => c.change(() => c.moving = v),
              ),
              if (c.comparisonRange != null)
                Text(
                  'Riferimento: ${rangeLabel(c.comparisonRange!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Fatto'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _phoneDataTools() => StatsPanel(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      title: Text(
        c.recovering
            ? 'Recupero ${c.recoveredDays} / ${c.recoveryTotal} giorni…'
            : 'Dati e sincronizzazione',
        style: const TextStyle(fontSize: 13),
      ),
      children: [
        Text(
          '${c.days.length} giorni salvati in Supabase. Il recupero usa le date del periodo selezionato.',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        if (!c.recovering)
          OutlinedButton.icon(
            onPressed: c.syncing ? null : c.recoverMissingDays,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Recupera giorni mancanti'),
          )
        else
          TextButton(
            onPressed: c.cancelRecovery,
            child: const Text('Interrompi dopo questo giorno'),
          ),
      ],
    ),
  );

  Widget _header() {
    if (usesPhoneLayout(context)) return _phoneHeader();
    final title = switch (c.section) {
      'Panoramica' => 'Il tuo corpo, nel tempo.',
      'Esperimenti' => 'Esperimenti personali',
      _ => c.section,
    };
    final subtitle = switch (c.section) {
      'Sonno' => 'Durata, regolarità e recupero nel tempo',
      'Esperimenti' => 'Una nuova abitudine. Un confronto nel tempo.',
      'Cuore e recupero' => 'Battito e variabilità, osservati nel tempo',
      'Attività' => 'Passi, distanza e movimento quotidiano',
      'Abitudini' => 'Coppe, costanza e riuscita di ogni abitudine',
      'Cellulare' => 'Il tempo conteggiato al telefono, giorno per giorno',
      'Sport' => 'Allenamenti, camminate, movimento e peso',
      'Percezione' => 'Emozioni, energia e intensità dal tuo diario personale',
      _ =>
        'Osserva gli andamenti. Confronta i periodi. Conosci le tue abitudini.',
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/alpine-header.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: .94),
                    Colors.white.withValues(alpha: .57),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: LayoutBuilder(
              builder: (context, box) => Wrap(
                spacing: 22,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: math.max(
                      160,
                      box.maxWidth - (box.maxWidth > 780 ? 290 : 0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          capitalize(formatItalianDate(c.today)),
                          style: const TextStyle(
                            color: AppColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.8,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatsPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          c.section == 'Percezione'
                              ? Icons.sentiment_satisfied_alt
                              : Icons.watch_outlined,
                          color:
                              c.section == 'Percezione' ||
                                  widget.fitbit.isConnected
                              ? AppColors.green
                              : AppColors.textMuted,
                          size: 25,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.section == 'Percezione'
                                    ? 'Diario personale'
                                    : widget.fitbit.isConnected
                                    ? 'Fitbit connesso'
                                    : 'Archivio Fitbit',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                c.section == 'Percezione'
                                    ? '${c.perceptions.length} registrazioni in Supabase'
                                    : c.days.isEmpty
                                    ? 'Nessun giorno salvato'
                                    : '${c.days.length} giorni in Supabase',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed:
                              c.syncing || c.perceptionsLoading || !c.loaded
                              ? null
                              : _refreshCurrentData,
                          tooltip: c.section == 'Percezione'
                              ? 'Aggiorna le emozioni dal diario'
                              : 'Sincronizza lo storico Fitbit',
                          icon: c.syncing || c.perceptionsLoading
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<BodyRange?> _pickRange(BodyRange initial) async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(c.today.year, c.today.month, c.today.day),
      initialDateRange: initial.end.isAfter(c.today)
          ? null
          : DateTimeRange(
              start: DateTime(
                initial.start.year,
                initial.start.month,
                initial.start.day,
              ),
              end: DateTime(
                initial.end.year,
                initial.end.month,
                initial.end.day,
              ),
            ),
      locale: const Locale('it'),
    );
    return result == null ? null : BodyRange(result.start, result.end);
  }

  Widget _timeControls() => usesPhoneLayout(context)
      ? _phoneTimeControls()
      : StatsPanel(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 9,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _segments<BodyPeriod>(
                BodyPeriod.values.map((p) => (p, p.label)).toList(),
                c.period,
                (p) async {
                  if (p == BodyPeriod.custom) {
                    final r = await _pickRange(c.range);
                    if (r == null) return;
                    c.change(() {
                      c.customRange = r;
                      c.period = p;
                    });
                  } else {
                    c.change(() => c.period = p);
                  }
                },
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Periodo precedente',
                    visualDensity: VisualDensity.compact,
                    onPressed: c.period == BodyPeriod.all
                        ? null
                        : () => _shift(-1),
                    icon: const Icon(Icons.chevron_left, size: 18),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final r = await _pickRange(c.range);
                      if (r != null) {
                        c.change(() {
                          c.customRange = r;
                          c.period = BodyPeriod.custom;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: Text(
                      rangeLabel(c.range),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Periodo successivo',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        c.period == BodyPeriod.all ||
                            !c.range.end.isBefore(c.today)
                        ? null
                        : () => _shift(1),
                    icon: const Icon(Icons.chevron_right, size: 18),
                  ),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Confronta con: ',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: !c.compare
                          ? 'none'
                          : c.customComparison == null
                          ? 'previous'
                          : 'custom',
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'previous',
                          child: Text('periodo precedente'),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text('intervallo personalizzato'),
                        ),
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('nessun confronto'),
                        ),
                      ],
                      onChanged: (v) async {
                        if (v == 'custom') {
                          final r = await _pickRange(
                            c.customComparison ?? c.range.previous,
                          );
                          if (r != null) {
                            c.change(() {
                              c.customComparison = r;
                              c.compare = true;
                            });
                          }
                        } else {
                          c.change(() {
                            c.compare = v != 'none';
                            c.customComparison = null;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: c.moving,
                    onChanged: (v) => c.change(() => c.moving = v),
                  ),
                  const Flexible(
                    child: Text(
                      'Media mobile 7 giorni',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              if (c.comparisonRange != null)
                Text(
                  'Riferimento: ${rangeLabel(c.comparisonRange!)} · ${c.comparisonRange!.days} giorni${c.comparisonRange!.days != c.range.days ? ' · durata diversa, confronta le medie' : ''}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        );
  void _shift(int direction) {
    final shifted = c.range.end.add(Duration(days: c.range.days * direction));
    final end = shifted.isAfter(c.today) ? c.today : shifted;
    c.change(() {
      c.customRange = BodyRange(
        end.subtract(Duration(days: c.range.days - 1)),
        end,
      );
      c.period = BodyPeriod.custom;
    });
  }

  Widget _tabs() => usesPhoneLayout(context)
      ? StatsPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('phone-statistics-section'),
              value: c.section,
              isExpanded: true,
              items: [
                for (final tab in bodySections)
                  DropdownMenuItem(
                    value: tab.$1,
                    child: Row(
                      children: [
                        Icon(tab.$2, color: AppColors.green, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tab.$1,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (s) {
                if (s != null) c.change(() => c.section = s);
              },
            ),
          ),
        )
      : SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tab in bodySections)
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: c.section == tab.$1
                            ? AppColors.green
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: TextButton.icon(
                    onPressed: () => c.change(() => c.section = tab.$1),
                    icon: Icon(tab.$2, size: 19),
                    label: Text(tab.$1, style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: c.section == tab.$1
                          ? AppColors.green
                          : AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 15,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
  Widget _segments<T>(
    List<(T, String)> items,
    T selected,
    ValueChanged<T> onChange,
  ) => Wrap(
    spacing: 1,
    runSpacing: 3,
    children: [
      for (final i in items)
        TextButton(
          onPressed: () => onChange(i.$1),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            backgroundColor: i.$1 == selected
                ? AppColors.green
                : AppColors.surfaceMuted,
            foregroundColor: i.$1 == selected
                ? Colors.white
                : AppColors.textMuted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(i.$2, style: const TextStyle(fontSize: 11)),
        ),
    ],
  );

  Widget _metric(BodyMetric metric, {bool total = false, String? label}) {
    final now = c.summary(metric, c.range);
    final before = c.comparisonRange == null
        ? null
        : c.summary(metric, c.comparisonRange!);
    final value = total ? now.total : now.mean;
    final previous = total ? before?.total : before?.mean;
    final diff = value == null || previous == null ? null : value - previous;
    return StatsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metricIcon(metric), color: metricColor(metric), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label ?? '${metric.label}${total ? ' · totale' : ' · media'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            metric.format(value),
            style: TextStyle(
              fontSize: usesPhoneLayout(context) ? 21 : 27,
              color: AppColors.text,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            diff == null
                ? 'Confronto non disponibile'
                : '${metric.format(diff, delta: true)} sul riferimento',
            style: TextStyle(
              color: metricColor(metric),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            now.coverageLabel,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          if (before != null)
            Text(
              'Rif. ${before.count} / ${before.expected} giorni',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _heading(
    String title,
    IconData icon,
    Color color, {
    String? subtitle,
    Widget? trailing,
  }) => Wrap(
    spacing: 16,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.text,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      ?trailing,
    ],
  );
  Widget _chartPanel(
    BodyMetric metric, {
    String? title,
    bool bars = false,
    bool alwaysAverage = false,
  }) {
    final values = c.series(metric, c.range);
    // Con almeno otto giorni la media mobile aiuta a leggere l'andamento.
    final moving =
        c.moving || (alwaysAverage && values.whereType<double>().length >= 8);
    final previous = c.comparisonRange == null
        ? null
        : c.series(metric, c.comparisonRange!);
    return StatsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            title ?? metric.label,
            metricIcon(metric),
            metricColor(metric),
            subtitle: 'Valori giornalieri · ${metric.unit}',
          ),
          const SizedBox(height: 14),
          ChartLegend(
            items: [
              (metric.label, metricColor(metric)),
              if (moving)
                (
                  'Media mobile 7 giorni',
                  bars ? AppColors.text : metricColor(metric),
                ),
              if (previous != null) ('Periodo precedente', AppColors.textFaint),
            ],
          ),
          const SizedBox(height: 8),
          BodyChart(
            values: values,
            labels: c.range.dates.map(shortStatsDate).toList(),
            metric: metric,
            previous: previous,
            average: moving,
            bars: bars,
          ),
          Text(
            '${c.summary(metric, c.range).coverageLabel}${previous == null ? '' : ' · riferimento allineato per giorno da inizio periodo'}',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  List<Widget> _overview() => [
    StatsGrid(
      columns: 4,
      minWidth: 220,
      children: [
        _metric(BodyMetric.sleep, label: 'Sonno medio'),
        _metric(BodyMetric.restingHr),
        _metric(BodyMetric.hrv),
        _metric(BodyMetric.distance, total: true),
      ],
    ),
    if (widget.compareSources case final sources?) ...[
      const SizedBox(height: 12),
      _comparePanel(sources),
    ],
    const SizedBox(height: 12),
    StatsGrid(
      children: [
        _chartPanel(BodyMetric.sleep, title: 'Sonno nel tempo', bars: true),
        _heartChart(),
      ],
    ),
    const SizedBox(height: 12),
    StatsGrid(children: [_weeklyActivity(), _experimentPreview()]),
  ];

  /// Confronto tra 2 o 3 parametri: resta chiuso finché non lo apri.
  Widget _comparePanel(CompareSources sources) => StatsPanel(
    tint: _compareOpen ? null : const Color(0xFFF4F9FC),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _compareOpen = !_compareOpen),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('🔍', style: TextStyle(fontSize: 19)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confronta parametri',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'HRV e meditazione, sonno e calorie… scegli 2 o 3 cose e guarda se vanno insieme.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _compareOpen = !_compareOpen),
                icon: Icon(
                  _compareOpen ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(_compareOpen ? 'Chiudi' : 'Apri'),
              ),
            ],
          ),
        ),
        if (_compareOpen) ...[
          const SizedBox(height: 16),
          ComparePanel(controller: c, sources: sources),
        ],
      ],
    ),
  );

  Widget _heartChart() => StatsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Battito a riposo e HRV',
          Icons.favorite_border,
          heartColor,
          subtitle: 'Andamento nel tempo',
          trailing: _segments<BodyMetric>(
            [(BodyMetric.restingHr, 'FC a riposo'), (BodyMetric.hrv, 'HRV')],
            c.heartMetric,
            (m) => c.change(() => c.heartMetric = m),
          ),
        ),
        const SizedBox(height: 12),
        ChartLegend(
          items: [
            (c.heartMetric.label, metricColor(c.heartMetric)),
            if (c.moving) ('Media mobile 7 giorni', metricColor(c.heartMetric)),
            if (c.compare) ('Riferimento', AppColors.textFaint),
          ],
        ),
        const SizedBox(height: 8),
        BodyChart(
          values: c.series(c.heartMetric, c.range),
          labels: c.range.dates.map(shortStatsDate).toList(),
          metric: c.heartMetric,
          previous: c.comparisonRange == null
              ? null
              : c.series(c.heartMetric, c.comparisonRange!),
          average: c.moving,
        ),
        Text(
          c.summary(c.heartMetric, c.range).coverageLabel,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
      ],
    ),
  );

  List<Widget> _sleep() => [
    StatsGrid(
      columns: 4,
      minWidth: 220,
      children: [
        _metric(BodyMetric.sleep, label: 'Durata media'),
        _metric(BodyMetric.efficiency, label: 'Efficienza media'),
        _sleepHours(),
        _nights(),
      ],
    ),
    const SizedBox(height: 12),
    _sleepChart(),
    const SizedBox(height: 12),
    StatsGrid(
      children: [
        StatsPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading('Regolarità degli orari', Icons.schedule, sleepColor),
              const SizedBox(height: 16),
              ChartLegend(
                items: [
                  ('Addormentamento', stageColors.first),
                  ('Risveglio', sleepColor),
                ],
              ),
              const SizedBox(height: 10),
              SleepRegularity(days: c.days, range: c.range),
            ],
          ),
        ),
        _comparisonTable([BodyMetric.sleep, BodyMetric.efficiency]),
      ],
    ),
    const SizedBox(height: 12),
    _observation(_sleepObservation()),
  ];
  Widget _sleepHours() {
    final pairs = <(double, double)>[];
    for (final d in c.days.where((d) => c.range.contains(d.date))) {
      final details = d.sleepDetails;
      final start = DateTime.tryParse(details?['startTime'] as String? ?? '');
      final end = DateTime.tryParse(details?['endTime'] as String? ?? '');
      if (start == null || end == null) continue;
      double minute(DateTime v) {
        final r = romeWallTime(v);
        return (r.hour < 18 ? r.hour + 24 : r.hour) * 60 + r.minute.toDouble();
      }

      pairs.add((minute(start), minute(end)));
    }
    String time(double v) {
      final n = v.round() % 1440;
      return '${(n ~/ 60).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}';
    }

    final value = pairs.isEmpty
        ? '—'
        : '${time(pairs.fold(0.0, (s, v) => s + v.$1) / pairs.length)} – ${time(pairs.fold(0.0, (s, v) => s + v.$2) / pairs.length)}';
    return _infoCard(
      'Orario medio',
      value,
      '${pairs.length} notti con orari · Europe/Rome',
      Icons.schedule,
      sleepColor,
    );
  }

  Widget _infoCard(
    String title,
    String value,
    String detail,
    IconData icon,
    Color color,
  ) => StatsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          value,
          style: TextStyle(
            fontSize: usesPhoneLayout(context) ? 21 : 25,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          detail,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
      ],
    ),
  );
  Widget _nights() {
    final s = c.summary(BodyMetric.sleep, c.range);
    return _infoCard(
      'Notti registrate',
      '${s.count} / ${s.expected}',
      '${(s.coverage * 100).round()}% copertura',
      Icons.calendar_month_outlined,
      sleepColor,
    );
  }

  List<double>? _stages(BodyDay? d) {
    final values = d?.sleepDetails?['stageMinutes'] as Map?;
    if (values == null ||
        !['deep', 'light', 'rem', 'awake'].every((key) => values[key] is num)) {
      return null;
    }
    final stages = [
      for (final key in ['deep', 'light', 'rem', 'awake'])
        (values[key] as num).toDouble(),
    ];
    return stages.take(3).fold(0.0, (a, b) => a + b) <= 0 ? null : stages;
  }

  Widget _sleepChart() {
    final byDate = {for (final d in c.days) statsKey(d.date): d};
    final groups = <List<DateTime>>[];
    if (c.weeklySleep) {
      for (final b in weeklyBuckets(c.days, c.range, BodyMetric.sleep)) {
        groups.add(b.range.dates.toList());
      }
    } else {
      groups.addAll(c.range.dates.map((d) => [d]));
    }
    final stacks = <List<double>?>[], values = <double?>[], labels = <String>[];
    for (final group in groups) {
      final allStages = group
          .map((d) => _stages(byDate[statsKey(d)]))
          .whereType<List<double>>()
          .toList();
      stacks.add(
        allStages.isEmpty
            ? null
            : [
                for (var i = 0; i < 4; i++)
                  allStages.fold(0.0, (s, v) => s + v[i]) / allStages.length,
              ],
      );
      values.add(
        c.sleepStages
            ? (allStages.isEmpty
                  ? null
                  : allStages.fold(
                          0.0,
                          (s, v) => s + v.take(3).fold(0.0, (a, b) => a + b),
                        ) /
                        allStages.length)
            : BodySummary(
                group.map((d) => byDate[statsKey(d)]?.value(BodyMetric.sleep)),
                group.length,
              ).mean,
      );
      labels.add(
        '${shortStatsDate(group.first)}${c.weeklySleep && (group.length < 7 || group.where((d) => byDate[statsKey(d)]?.value(BodyMetric.sleep) != null).length < 7) ? '*' : ''}',
      );
    }
    return StatsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'Le tue notti, a confronto',
            Icons.bar_chart,
            sleepColor,
            trailing: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _segments<bool>(
                  [(false, 'Durata'), (true, 'Fasi')],
                  c.sleepStages,
                  (v) => c.change(() => c.sleepStages = v),
                ),
                _segments<bool>(
                  [(false, 'Giorno'), (true, 'Settimana')],
                  c.weeklySleep,
                  (v) => c.change(() => c.weeklySleep = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          BodyChart(
            values: values,
            labels: labels,
            metric: BodyMetric.sleep,
            bars: true,
            stacks: c.sleepStages ? stacks : null,
            average: !c.weeklySleep && !c.sleepStages && c.moving,
            previous:
                !c.weeklySleep && !c.sleepStages && c.comparisonRange != null
                ? c.series(BodyMetric.sleep, c.comparisonRange!)
                : null,
            height: 220,
          ),
          if (c.sleepStages)
            ChartLegend(
              items: [
                for (var i = 0; i < 4; i++)
                  (
                    const ['Profondo', 'Leggero', 'REM', 'Sveglio'][i],
                    stageColors[i],
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            c.weeklySleep
                ? 'Medie per notte registrata · * settimana incompleta · le fasi includono i minuti di veglia disponibili'
                : 'Stime Fitbit delle fasi del sonno · le notti senza fasi rimangono vuote',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          Text(
            c.sleepStages
                ? '${stacks.whereType<List<double>>().length} / ${groups.length} ${c.weeklySleep ? 'settimane' : 'notti'} con fasi disponibili'
                : c.summary(BodyMetric.sleep, c.range).coverageLabel,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  String _sleepObservation() {
    final late = <double>[], early = <double>[];
    for (final d in c.days.where((d) => c.range.contains(d.date))) {
      final instant = DateTime.tryParse(
        d.sleepDetails?['startTime'] as String? ?? '',
      );
      final duration = d.value(BodyMetric.sleep);
      if (instant == null || duration == null) continue;
      final hour = romeWallTime(instant).hour;
      (hour >= 1 && hour < 12 ? late : early).add(duration);
    }
    if (late.length < 2 || early.length < 2) {
      return 'Dati insufficienti per confrontare gli orari: servono almeno 2 notti con addormentamento dopo le 01:00 e 2 prima, con durata disponibile.';
    }
    final a = BodySummary(late, late.length).mean!,
        b = BodySummary(early, early.length).mean!;
    return 'Nelle ${late.length} notti con addormentamento fra le 01:00 e le 12:00 la durata media è ${BodyMetric.sleep.format(a)}, rispetto a ${BodyMetric.sleep.format(b)} nelle altre ${early.length}. Associazione descrittiva, non causale.';
  }

  Widget _comparisonTable(List<BodyMetric> metrics) => StatsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Rispetto al riferimento',
          Icons.trending_up,
          sleepColor,
          subtitle: c.comparisonRange == null
              ? 'Seleziona un confronto'
              : rangeLabel(c.comparisonRange!),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(520, box.maxWidth),
              child: DataTable(
                horizontalMargin: 10,
                columnSpacing: 14,
                headingRowHeight: 38,
                dataRowMinHeight: 55,
                dataRowMaxHeight: 65,
                columns: const [
                  DataColumn(label: Text('Metrica')),
                  DataColumn(label: Text('Prima')),
                  DataColumn(label: Text('Attuale')),
                  DataColumn(label: Text('Variazione')),
                ],
                rows: [
                  for (final m in metrics)
                    () {
                      final a = c.comparisonRange == null
                              ? null
                              : c.summary(m, c.comparisonRange!),
                          b = c.summary(m, c.range);
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(m.label, style: const TextStyle(fontSize: 11)),
                          ),
                          DataCell(
                            Text(
                              '${m.format(a?.mean)}\n${a?.count ?? 0} osservazioni',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${m.format(b.mean)}\n${b.count} osservazioni',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          DataCell(
                            Text(
                              a?.mean == null || b.mean == null
                                  ? '—'
                                  : m.format(b.mean! - a!.mean!, delta: true),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      );
                    }(),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _observation(String text) => StatsPanel(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lightbulb_outline, color: sleepColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Osservazione',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
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

  List<Widget> _heart() => [
    StatsGrid(
      columns: 4,
      minWidth: 220,
      children: [
        _metric(BodyMetric.restingHr),
        _metric(BodyMetric.hrv),
        _infoCard(
          'Giorni con HRV',
          '${c.summary(BodyMetric.hrv, c.range).count}',
          c.summary(BodyMetric.hrv, c.range).coverageLabel,
          Icons.monitor_heart_outlined,
          hrvColor,
        ),
        _infoCard(
          'Granularità',
          'Giornaliera',
          'HRV notturna · FC a riposo giornaliera',
          Icons.timeline,
          heartColor,
        ),
      ],
    ),
    const SizedBox(height: 12),
    StatsGrid(
      children: [
        _chartPanel(BodyMetric.restingHr),
        _chartPanel(BodyMetric.hrv),
      ],
    ),
    const SizedBox(height: 12),
    _heartRatePeriod(),
    const SizedBox(height: 12),
    _comparisonTable([BodyMetric.restingHr, BodyMetric.hrv]),
  ];
  Widget _heartRatePeriod() {
    final current = HeartRateStatistics(c.days, c.range);
    final reference = c.comparisonRange == null
        ? null
        : HeartRateStatistics(c.days, c.comparisonRange!);
    final singleDay = c.range.days == 1;
    final clockProfile = !singleDay && c.averageHeartDay;
    final values = singleDay
        ? current.intradayMeans
        : clockProfile
        ? current.clockMeans
        : current.dailyMeans;
    final labels = singleDay
        ? current.intradayLabels
        : clockProfile
        ? List.generate(48, HeartRateStatistics.clockLabel)
        : c.range.dates.map(shortStatsDate).toList();
    final previous = singleDay
        ? null
        : clockProfile
        ? reference?.clockMeans
        : reference?.dailyMeans;
    final moving = !singleDay && !clockProfile && c.moving;
    final summary = current.summary;
    return StatsPanel(
      key: const ValueKey('heart-rate-period-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            '${singleDay
                ? 'Frequenza cardiaca'
                : clockProfile
                ? 'Frequenza cardiaca · giornata media'
                : 'Frequenza cardiaca · medie giornaliere'} · ${rangeLabel(c.range)}',
            Icons.favorite_border,
            heartColor,
            subtitle: singleDay
                ? 'Intervalli reali di 30 minuti · bpm'
                : clockProfile
                ? 'Media per fascia oraria su tutti i giorni disponibili · Europe/Rome · bpm'
                : 'Una media per ogni giornata del periodo selezionato · bpm',
            trailing: singleDay
                ? null
                : _segments<bool>(
                    [(false, 'Nel tempo'), (true, 'Giornata media')],
                    c.averageHeartDay,
                    (value) => c.change(() => c.averageHeartDay = value),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            'Media ${singleDay ? 'del giorno' : 'delle medie giornaliere'}: ${BodyMetric.restingHr.format(summary.mean)} · ${summary.coverageLabel} · ${current.count} intervalli disponibili',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          if (reference != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Riferimento ${rangeLabel(reference.range)}: ${BodyMetric.restingHr.format(reference.summary.mean)} · ${reference.summary.coverageLabel}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 12),
          ChartLegend(
            items: [
              (
                singleDay
                    ? 'Media per intervallo'
                    : clockProfile
                    ? 'Profilo orario medio'
                    : 'Media giornaliera',
                heartColor,
              ),
              if (moving) ('Media mobile 7 giorni', heartColor),
              if (previous != null) ('Riferimento', AppColors.textFaint),
            ],
          ),
          const SizedBox(height: 8),
          BodyChart(
            key: const ValueKey('heart-rate-period-chart'),
            values: values,
            labels: labels,
            metric: BodyMetric.restingHr,
            seriesLabel: 'Frequenza cardiaca media',
            previous: previous,
            average: moving,
            pointDetails: singleDay
                ? current.intradaySummaries
                      .map((s) => '${s.count} intervalli disponibili')
                      .toList()
                : clockProfile
                ? current.clockDetails
                : current.dailyDetails,
          ),
          Text(
            singleDay
                ? 'Le fasce senza misurazioni restano vuote.'
                : clockProfile
                ? 'Ogni giorno contribuisce una volta per fascia di 30 minuti; i giorni senza dati nella fascia sono esclusi. Il dettaglio indica quanti giorni contribuiscono.'
                : 'Media degli intervalli Fitbit disponibili per ogni giorno; giornate senza dati lasciate vuote. Ogni giorno ha lo stesso peso nella media del periodo.${previous == null ? '' : ' Riferimento allineato per giorno da inizio periodo.'}',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  List<Widget> _activity() => [
    StatsGrid(
      columns: 4,
      minWidth: 220,
      children: [
        _metric(BodyMetric.steps, total: true),
        _metric(BodyMetric.distance, total: true),
        _metric(BodyMetric.active, total: true),
        _metric(BodyMetric.steps, label: 'Passi medi al giorno'),
      ],
    ),
    const SizedBox(height: 12),
    StatsGrid(
      children: [_weeklyActivity(), _chartPanel(BodyMetric.active, bars: true)],
    ),
    const SizedBox(height: 12),
    StatsGrid(
      children: [
        _chartPanel(BodyMetric.steps, bars: true, alwaysAverage: true),
        _chartPanel(BodyMetric.distance, bars: true, alwaysAverage: true),
      ],
    ),
  ];
  Widget _weeklyActivity() {
    final m = c.activitySteps ? BodyMetric.steps : BodyMetric.distance;
    final buckets = weeklyBuckets(c.days, c.range, m);
    return StatsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            c.activitySteps
                ? 'Passi per settimana'
                : 'Chilometri per settimana',
            Icons.directions_walk,
            AppColors.green,
            subtitle: 'Totale per settimana · ${m.unit}',
            trailing: _segments<bool>(
              [(true, 'Passi'), (false, 'Distanza')],
              c.activitySteps,
              (v) => c.change(() => c.activitySteps = v),
            ),
          ),
          const SizedBox(height: 12),
          BodyChart(
            values: buckets.map((b) => b.summary.total).toList(),
            labels: buckets
                .map(
                  (b) =>
                      '${shortStatsDate(b.range.start)}${b.partial ? '*' : ''}',
                )
                .toList(),
            metric: m,
            bars: true,
            height: 195,
          ),
          Text(
            '* Settimana incompleta · totali sui soli giorni disponibili',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 5,
            children: [
              for (final b in buckets)
                Text(
                  '${shortStatsDate(b.range.start)}: ${b.summary.count}/${b.range.days} giorni',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _experimentPreview() => StatsPanel(
    tint: const Color(0xFFF0FBF7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'I tuoi esperimenti',
          Icons.science_outlined,
          AppColors.green,
          trailing: OutlinedButton.icon(
            onPressed: () => showExperimentForm(context, c),
            icon: const Icon(Icons.add, size: 16),
            label: const Text(
              'Nuovo esperimento',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (c.experiments
            .where((e) => e.status != ExperimentStatus.archived)
            .isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Registra un’abitudine per confrontare i dati prima e durante la pratica. Le sessioni si registrano nel diario.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          )
        else
          for (final e
              in c.experiments
                  .where((e) => e.status != ExperimentStatus.archived)
                  .take(2))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.science_outlined,
                color: AppColors.green,
              ),
              title: Text(
                e.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${e.status.label} · ${rangeLabel(e.range)}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.arrow_forward, size: 18),
              onTap: () {
                c.change(() => c.section = 'Esperimenti');
                c.selectExperiment(e.id!);
              },
            ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => c.change(() => c.section = 'Esperimenti'),
          icon: const Icon(Icons.bar_chart, size: 18),
          label: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Confronta prima e durante',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _experiments() {
    final e = c.selected;
    final a = c.analysis;
    final visible = c.experiments
        .where(
          (e) =>
              c.showArchived ||
              e.status != ExperimentStatus.archived ||
              e.id == c.selectedId,
        )
        .toList();
    return [
      Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () => showExperimentForm(context, c),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nuovo esperimento'),
          ),
          FilterChip(
            label: const Text('Mostra archiviati'),
            selected: c.showArchived,
            onSelected: (v) => c.change(() => c.showArchived = v),
          ),
          if (visible.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: DropdownButtonFormField<String>(
                key: ValueKey('experiments-${c.selectedId}-${visible.length}'),
                initialValue: visible.any((v) => v.id == c.selectedId)
                    ? c.selectedId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Seleziona esperimento',
                ),
                isExpanded: true,
                items: [
                  for (final experiment in visible)
                    DropdownMenuItem(
                      value: experiment.id,
                      child: Text(
                        '${experiment.name} · ${experiment.status.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) c.selectExperiment(id);
                },
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (e == null || a == null)
        _experimentPreview()
      else ...[
        _experimentHeader(e, a),
        const SizedBox(height: 12),
        if (c.logsLoading) const LinearProgressIndicator(),
        if (!c.logsLoading) ...[
          StatsGrid(
            columns: 4,
            minWidth: 220,
            children: [for (final m in e.metrics) _experimentMetric(e, a, m)],
          ),
          const SizedBox(height: 12),
          StatsGrid(
            minWidth: 380,
            children: [_experimentChart(e, a), _factors(e, a)],
          ),
          const SizedBox(height: 12),
          _observation(
            '${a.provisional ? 'Confronto provvisorio · ${a.availableDays} / ${e.range.days} giorni disponibili. ' : ''}${a.observation(c.experimentMetric)} Le altre abitudini e la variabilità naturale possono influire.',
          ),
          const SizedBox(height: 12),
          _diary(e, a),
        ],
      ],
    ];
  }

  Widget _experimentHeader(
    BodyExperiment e,
    ExperimentComparison a,
  ) => StatsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          e.name,
          Icons.science_outlined,
          AppColors.green,
          subtitle: e.description,
          trailing: Chip(
            label: Text(e.status.label, style: const TextStyle(fontSize: 11)),
            backgroundColor: AppColors.greenSoft,
            side: BorderSide.none,
          ),
        ),
        if (e.objective.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(e.objective, style: const TextStyle(fontSize: 12)),
          ),
        const SizedBox(height: 14),
        StatsGrid(
          columns: 3,
          minWidth: 220,
          children: [
            StatsPanel(
              tint: const Color(0xFFF2F2F4),
              padding: const EdgeInsets.all(12),
              child: Text(
                'Prima · ${rangeLabel(e.baseline)}\n${e.baseline.days} giorni',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            StatsPanel(
              tint: AppColors.greenSoft,
              padding: const EdgeInsets.all(12),
              child: Text(
                'Durante · ${rangeLabel(e.range)}\n${e.range.days} giorni',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sessioni completate · ${a.completed} / ${e.plannedSessions}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: e.plannedSessions == 0
                      ? 0
                      : (a.completed / e.plannedSessions).clamp(0, 1),
                  borderRadius: BorderRadius.circular(8),
                  minHeight: 8,
                ),
                const SizedBox(height: 6),
                Text(
                  '${a.availableDays} giorni effettivamente disponibili',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${e.activity} · ${e.plannedMinutes} min · ${e.weekdays.length} giorni/settimana${e.plannedTime == null ? '' : ' · ${e.plannedTime} Europe/Rome'}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        if (e.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Note iniziali: ${e.notes}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if (e.repeatedFrom != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () => c.selectExperiment(e.repeatedFrom!),
              child: const Text('Apri il test precedente'),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => showExperimentForm(context, c, experiment: e),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Modifica'),
            ),
            if (e.status == ExperimentStatus.draft)
              FilledButton(
                onPressed: c.saving
                    ? null
                    : () => _status(e, ExperimentStatus.running),
                child: const Text('Avvia'),
              ),
            if (e.status == ExperimentStatus.running)
              FilledButton(
                onPressed: c.saving
                    ? null
                    : () => _status(e, ExperimentStatus.completed),
                child: const Text('Concludi'),
              ),
            if (e.status != ExperimentStatus.archived)
              TextButton(
                onPressed: c.saving
                    ? null
                    : () => _status(e, ExperimentStatus.archived),
                child: const Text('Archivia'),
              ),
            if (e.status == ExperimentStatus.archived)
              TextButton(
                onPressed: c.saving
                    ? null
                    : () => _status(e, ExperimentStatus.draft),
                child: const Text('Ripristina bozza'),
              ),
            OutlinedButton.icon(
              onPressed: () =>
                  showExperimentForm(context, c, experiment: e, repeat: true),
              icon: const Icon(Icons.replay, size: 16),
              label: const Text('Ripeti il test'),
            ),
            FilledButton.icon(
              onPressed: e.baseline.start.isAfter(c.today)
                  ? null
                  : () => showLogForm(context, c),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Registra giornata'),
            ),
          ],
        ),
      ],
    ),
  );
  Future<void> _status(BodyExperiment e, ExperimentStatus status) async {
    await c.saveExperiment(
      BodyExperiment.fromJson({...e.toJson(), 'status': status.name}),
    );
  }

  Widget _experimentMetric(
    BodyExperiment e,
    ExperimentComparison a,
    BodyMetric m,
  ) {
    final before = a.summary(e.baseline, m), during = a.summary(e.range, m);
    final enough = before.count >= 2 && during.count >= 2;
    return StatsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metricIcon(m), color: metricColor(m), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  m.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${m.format(before.mean)} → ${m.format(during.mean)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            enough
                ? m.format(during.mean! - before.mean!, delta: true)
                : 'Dati insufficienti per il confronto',
            style: TextStyle(fontSize: 12, color: metricColor(m)),
          ),
          const SizedBox(height: 8),
          Text(
            'Prima: ${before.coverageLabel}\nDurante: ${during.coverageLabel}',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          Text(
            'Dev. standard: ${m.format(before.sd)} → ${m.format(during.sd)}',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          if (m.manual || m.perception)
            Text(
              m.perception
                  ? 'Fonte: emozioni del diario · calma 1–5 · media giornaliera'
                  : 'Fonte: diario manuale',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _experimentChart(BodyExperiment e, ExperimentComparison a) {
    final m = c.experimentMetric,
        dates = BodyRange(e.baseline.start, e.range.end).dates.toList();
    return StatsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'Prima e durante',
            metricIcon(m),
            metricColor(m),
            trailing: _segments<BodyMetric>(
              e.metrics.map((m) => (m, m.label)).toList(),
              m,
              (v) => c.change(() => c.experimentMetric = v),
            ),
          ),
          const SizedBox(height: 12),
          BodyChart(
            values: dates
                .map(
                  (d) => e.baseline.contains(d) || e.range.contains(d)
                      ? a.value(d, m)
                      : null,
                )
                .toList(),
            labels: dates.map(shortStatsDate).toList(),
            metric: m,
            boundary: e.range.start.difference(e.baseline.start).inDays,
            beforeMean: a.summary(e.baseline, m).mean,
            duringMean: a.summary(e.range, m).mean,
            height: 245,
          ),
          ChartLegend(
            items: [
              (
                m.perception
                    ? 'Calma dal diario · 1–5'
                    : 'Valore ${m.manual ? 'manuale' : 'Fitbit'}',
                metricColor(m),
              ),
              ('Media del periodo', AppColors.green),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Esclusioni esplicite: ${a.excludedCount(e.baseline)} giorni prima · ${a.excludedCount(e.range)} durante',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _factors(BodyExperiment e, ExperimentComparison a) => StatsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Fattori da considerare', Icons.checklist, AppColors.green),
        const SizedBox(height: 14),
        for (final f in contextFactors.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(f.value, style: const TextStyle(fontSize: 12)),
                ),
                Text(
                  '${_factorCount(e.baseline, f.key)} → ${_factorCount(e.range, f.key)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        const Divider(),
        const Text(
          'Giorni con fattore / giorni con risposta · prima → durante. Nessuna risposta non equivale a “no”.',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        const Text(
          'Escludi dal confronto',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final f in contextFactors.entries)
              FilterChip(
                label: Text(f.value, style: const TextStyle(fontSize: 10)),
                selected: c.excludedFactors.contains(f.key),
                onSelected: (v) => c.change(() {
                  if (v) {
                    c.excludedFactors.add(f.key);
                  } else {
                    c.excludedFactors.remove(f.key);
                  }
                }),
              ),
          ],
        ),
        TextButton.icon(
          onPressed: e.baseline.start.isAfter(c.today)
              ? null
              : () => showLogForm(context, c),
          icon: const Icon(Icons.note_add_outlined, size: 17),
          label: const Text('Aggiungi una nota'),
        ),
      ],
    ),
  );
  String _factorCount(BodyRange range, String factor) {
    final logs = c.logs
        .where(
          (l) =>
              range.contains(l.date) &&
              !l.date.isAfter(c.today) &&
              l.context[factor] != null,
        )
        .toList();
    return '${logs.where((l) => l.context[factor] == true).length}/${logs.length}';
  }

  Widget _diary(BodyExperiment e, ExperimentComparison a) => StatsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Diario della pratica',
          Icons.edit_note,
          AppColors.green,
          subtitle:
              'Registrazioni manuali · completata, parziale, saltata o non registrata',
        ),
        const SizedBox(height: 12),
        if (c.logs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Nessuna giornata registrata. Le sessioni non vengono dedotte dai dati Fitbit.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          )
        else
          for (final l in c.logs.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                l.sessionStatus == 'completed'
                    ? Icons.check_circle_outline
                    : l.sessionStatus == 'partial'
                    ? Icons.timelapse
                    : l.sessionStatus == 'skipped'
                    ? Icons.remove_circle_outline
                    : Icons.edit_note,
                color: AppColors.green,
              ),
              title: Text(
                '${shortStatsDate(l.date)} · ${e.baseline.contains(l.date) ? 'Prima' : 'Durante'} · ${switch (l.sessionStatus) {
                  'completed' => 'Completata',
                  'partial' => 'Parziale',
                  'skipped' => 'Saltata',
                  _ => 'Pratica non registrata',
                }}',
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                '${l.minutes == null ? '' : '${l.minutes} min · '}${l.notes.isEmpty ? 'Nessuna nota' : l.notes}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.edit_outlined, size: 16),
              onTap: () => showLogForm(context, c, log: l),
            ),
      ],
    ),
  );
}
