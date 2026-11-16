import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../application/body_statistics_controller.dart';
import '../data/compare_sources.dart';
import '../domain/body_statistics.dart';

/// Un parametro che si può mettere a confronto.
class CompareParam {
  const CompareParam(
    this.id,
    this.label,
    this.emoji,
    this.unit,
    this.group, {
    this.metric,
    this.source,
    this.binary = false,
    this.decimals = 0,
  });
  final String id, label, emoji, unit, group;
  final BodyMetric? metric;
  final CompareSource? source;

  /// Sì/no (per esempio «ho meditato»): il grafico lo mostra come fasce.
  final bool binary;
  final int decimals;

  String format(double? v) {
    if (v == null || !v.isFinite) return '—';
    final n = v.toStringAsFixed(decimals).replaceAll('.', ',');
    return unit.isEmpty ? n : (unit.startsWith('/') ? '$n$unit' : '$n $unit');
  }
}

const compareParams = <CompareParam>[
  CompareParam('hrv', 'HRV', '❤️', 'ms', 'Corpo', metric: BodyMetric.hrv),
  CompareParam(
    'rhr',
    'FC a riposo',
    '💓',
    'bpm',
    'Corpo',
    metric: BodyMetric.restingHr,
  ),
  CompareParam(
    'sleep',
    'Sonno',
    '😴',
    'h',
    'Corpo',
    metric: BodyMetric.sleep,
    decimals: 1,
  ),
  CompareParam(
    'efficiency',
    'Efficienza sonno',
    '🛌',
    '%',
    'Corpo',
    metric: BodyMetric.efficiency,
  ),
  CompareParam(
    'steps',
    'Passi',
    '👟',
    'passi',
    'Corpo',
    metric: BodyMetric.steps,
  ),
  CompareParam(
    'active',
    'Minuti attivi',
    '🏃',
    'min',
    'Corpo',
    metric: BodyMetric.active,
  ),
  CompareParam(
    'meditation',
    'Meditazione',
    '🧘',
    '',
    'Mente',
    source: CompareSource.meditation,
    binary: true,
  ),
  CompareParam(
    'focus',
    'Concentrazione',
    '🎯',
    '/5',
    'Mente',
    source: CompareSource.dayConcentration,
    decimals: 1,
  ),
  CompareParam(
    'meditationFocus',
    'Concentrazione in meditazione',
    '🪷',
    '/5',
    'Mente',
    source: CompareSource.meditationConcentration,
    decimals: 1,
  ),
  CompareParam(
    'energy',
    'Energia',
    '⚡',
    '/4',
    'Mente',
    source: CompareSource.energy,
    decimals: 1,
  ),
  CompareParam(
    'mood',
    'Emozioni positive',
    '😊',
    '%',
    'Mente',
    source: CompareSource.mood,
  ),
  CompareParam(
    'screen',
    'Cellulare',
    '📱',
    'min',
    'Abitudini',
    source: CompareSource.screen,
  ),
  CompareParam(
    'movement',
    'Movimento',
    '🚶',
    '/5',
    'Abitudini',
    source: CompareSource.movement,
    decimals: 1,
  ),
  CompareParam(
    'calories',
    'Calorie mangiate',
    '🔥',
    'kcal',
    'Alimentazione',
    source: CompareSource.calories,
  ),
];

CompareParam _param(String id) => compareParams.firstWhere((p) => p.id == id);

const compareColors = [Color(0xFF0096C7), Color(0xFFF2711C), Color(0xFF8651FF)];

const _presets = <(String, List<String>)>[
  ('❤️ HRV · 🧘 Meditazione', ['hrv', 'meditation']),
  ('❤️ HRV · 🎯 Concentrazione', ['hrv', 'focus']),
  ('😴 Sonno · 🔥 Calorie', ['sleep', 'calories']),
  ('😴 Sonno · ⚡ Energia · 🎯 Concentrazione', ['sleep', 'energy', 'focus']),
];

/// Una serie pronta per il grafico: un valore per punto (giorno o settimana).
class _Series {
  _Series(this.param, this.color, this.values, {this.share = false});
  final CompareParam param;
  final Color color;
  final List<double?> values;

  /// Sì/no raggruppato per settimana: è la quota di giorni (0–1).
  final bool share;
  bool get bands => param.binary;
  Iterable<double> get present => values.whereType<double>();
  int get count => present.length;
}

enum _View { time, scatter, split }

class ComparePanel extends StatefulWidget {
  const ComparePanel({
    required this.controller,
    required this.sources,
    super.key,
  });
  final BodyStatisticsController controller;
  final CompareSources sources;

  @override
  State<ComparePanel> createState() => _ComparePanelState();
}

class _ComparePanelState extends State<ComparePanel> {
  List<String> _selected = ['hrv', 'meditation'];
  final _cache = <String, Map<String, double>>{};
  final _loading = <String>{};
  Object? _error;
  String? _hint;
  _View? _view;
  int? _touch;

  BodyStatisticsController get c => widget.controller;
  BodyRange get _range => c.range;

  String _cacheKey(CompareSource s) =>
      '${s.name}|${statsKey(_range.start)}|${statsKey(_range.end)}';

  @override
  void initState() {
    super.initState();
    c.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    c.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final range = _range;
    for (final id in _selected) {
      final source = _param(id).source;
      if (source == null) continue;
      final k = _cacheKey(source);
      if (_cache.containsKey(k) || _loading.contains(k)) continue;
      _loading.add(k);
      if (mounted) setState(() => _error = null);
      try {
        final data = await widget.sources.load(source, range.start, range.end);
        _cache[k] = data;
      } on Object catch (e) {
        _error = e;
      } finally {
        _loading.remove(k);
        if (mounted) setState(() {});
      }
    }
  }

  void _toggle(String id) {
    setState(() {
      _hint = null;
      _touch = null;
      _view = null;
      if (_selected.contains(id)) {
        _selected = [..._selected]..remove(id);
      } else if (_selected.length >= 3) {
        _hint = 'Puoi confrontare al massimo 3 parametri: togline uno.';
      } else {
        _selected = [..._selected, id];
      }
    });
    _load();
  }

  void _preset(List<String> ids) {
    setState(() {
      _selected = [...ids];
      _hint = null;
      _touch = null;
      _view = null;
    });
    _load();
  }

  /// Valori per giorno del parametro, allineati alle date del periodo.
  List<double?> _daily(CompareParam p) {
    if (p.metric case final metric?) {
      final values = c.series(metric, _range);
      return metric == BodyMetric.sleep
          ? [for (final v in values) v == null ? null : v / 60]
          : values;
    }
    final data = _cache[_cacheKey(p.source!)] ?? const {};
    return [for (final d in _range.dates) data[statsKey(d)]];
  }

  /// Oltre i tre mesi i punti diventano settimane: il grafico resta leggibile.
  bool get _weekly => _range.days > 92;

  (List<String>, List<_Series>) _build() {
    final dates = _range.dates.toList();
    final series = <_Series>[];
    for (var i = 0; i < _selected.length; i++) {
      final p = _param(_selected[i]);
      final daily = _daily(p);
      if (!_weekly) {
        series.add(_Series(p, compareColors[i], daily));
        continue;
      }
      final values = <double?>[];
      for (var s = 0; s < daily.length; s += 7) {
        final chunk = daily
            .sublist(s, math.min(s + 7, daily.length))
            .whereType<double>()
            .toList();
        values.add(
          chunk.isEmpty ? null : chunk.reduce((a, b) => a + b) / chunk.length,
        );
      }
      series.add(_Series(p, compareColors[i], values, share: p.binary));
    }
    final labels = <String>[
      for (var s = 0; s < dates.length; s += _weekly ? 7 : 1)
        '${dates[s].day}/${dates[s].month}',
    ];
    return (labels, series);
  }

  @override
  Widget build(BuildContext context) {
    final (labels, series) = _build();
    final loading = _loading.isNotEmpty;
    final continuous = series.where((s) => !s.bands).toList();
    final binary = series.where((s) => s.bands).toList();
    final canSplit =
        series.length == 2 && binary.length == 1 && continuous.length == 1;
    final canScatter = series.length == 2 && continuous.length == 2;
    final view = _view ?? (canSplit ? _View.split : _View.time);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _picker(),
        if (_hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _hint!,
              style: const TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(
            'Non riesco a leggere alcuni dati: ${_error is StateError ? (_error as StateError).message : 'riprova più tardi'}.',
            style: const TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        if (series.length < 2)
          _empty('Scegli almeno 2 parametri per vederli insieme.')
        else ...[
          _insight(series),
          const SizedBox(height: 14),
          if (canSplit || canScatter)
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_View>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  if (canSplit)
                    ButtonSegment(
                      value: _View.split,
                      label: Text('${binary.first.param.emoji} Con / senza'),
                    ),
                  const ButtonSegment(
                    value: _View.time,
                    label: Text('📈 Nel tempo'),
                  ),
                  if (canScatter)
                    const ButtonSegment(
                      value: _View.scatter,
                      label: Text('🔵 Uno contro l’altro'),
                    ),
                ],
                selected: {view},
                onSelectionChanged: (v) => setState(() {
                  _view = v.first;
                  _touch = null;
                }),
              ),
            ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          switch (view) {
            _View.split => _split(continuous.first, binary.first),
            _View.scatter => _scatter(continuous[0], continuous[1]),
            _View.time => _timeline(labels, series),
          },
          const SizedBox(height: 10),
          Text(
            '${_weekly ? 'Medie settimanali' : 'Un punto al giorno'} · periodo scelto sopra (${_range.start.day}/${_range.start.month} – ${_range.end.day}/${_range.end.month}) · è un confronto, non dimostra una causa.',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _empty(String text) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: const TextStyle(fontSize: 13)),
  );

  Widget _picker() {
    final groups = <String, List<CompareParam>>{};
    for (final p in compareParams) {
      (groups[p.group] ??= []).add(p);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Prova subito',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, ids) in _presets)
              ActionChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                onPressed: () => _preset(ids),
                backgroundColor: _sameSelection(ids)
                    ? AppColors.greenSoft
                    : AppColors.surfaceMuted,
                side: BorderSide.none,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Oppure scegli tu (fino a 3) · ${_selected.length}/3',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        for (final g in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              g.key.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.textFaint,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final p in g.value) _chip(p)],
          ),
        ],
      ],
    );
  }

  bool _sameSelection(List<String> ids) =>
      ids.length == _selected.length && ids.every(_selected.contains);

  Widget _chip(CompareParam p) {
    final index = _selected.indexOf(p.id);
    final on = index >= 0;
    final color = on ? compareColors[index] : null;
    return Material(
      color: on ? color!.withValues(alpha: 0.14) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: on ? color! : AppColors.controlBorder,
          width: on ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _toggle(p.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (on)
                Container(
                  width: 17,
                  height: 17,
                  margin: const EdgeInsets.only(right: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Text(
                '${p.emoji} ${p.label}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- insight

  Widget _insight(List<_Series> series) {
    final lines = <String>[];
    final first = series.first;
    for (final other in series.skip(1)) {
      lines.add(_pairText(first, other));
    }
    if (series.length == 3) lines.add(_pairText(series[1], series[2]));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF8FB), Color(0xFFF5F0FF)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '💡 Cosa vedo',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                line,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  String _pairText(_Series a, _Series b) {
    final pa = a.param, pb = b.param;
    if (a.bands && b.bands) {
      var both = 0, any = 0;
      for (var i = 0; i < a.values.length; i++) {
        final x = a.values[i], y = b.values[i];
        if (x == null || y == null) continue;
        any++;
        if (x > 0.5 && y > 0.5) both++;
      }
      return any == 0
          ? '${pa.emoji} ${pa.label} e ${pb.emoji} ${pb.label}: nessun giorno con entrambi i dati.'
          : '${pa.emoji} ${pa.label} e ${pb.emoji} ${pb.label} insieme in $both giorni su $any.';
    }
    if (a.bands || b.bands) {
      final flag = a.bands ? a : b, value = a.bands ? b : a;
      if (flag.share) {
        return _correlationText(value, flag, shareLabel: true);
      }
      final yes = <double>[], no = <double>[];
      for (var i = 0; i < flag.values.length; i++) {
        final f = flag.values[i], v = value.values[i];
        if (f == null || v == null) continue;
        (f > 0.5 ? yes : no).add(v);
      }
      final pv = value.param, pf = flag.param;
      if (yes.length < 2 || no.length < 2) {
        return '${pv.emoji} ${pv.label} con e senza ${pf.emoji} ${pf.label.toLowerCase()}: servono almeno 2 giorni per parte (ora ${yes.length} con, ${no.length} senza).';
      }
      final my = yes.reduce((x, y) => x + y) / yes.length;
      final mn = no.reduce((x, y) => x + y) / no.length;
      final diff = my - mn;
      final pct = mn == 0 ? null : diff / mn.abs() * 100;
      final same = pct != null && pct.abs() < 3;
      return same
          ? 'Nei giorni con ${pf.label.toLowerCase()} ${pv.label} è quasi uguale: ${pv.format(my)} contro ${pv.format(mn)} (${yes.length} e ${no.length} giorni).'
          : 'Nei giorni con ${pf.emoji} ${pf.label.toLowerCase()} ${pv.emoji} ${pv.label} è in media ${pv.format(my)}, senza ${pv.format(mn)}: ${diff > 0 ? '+' : ''}${pv.format(diff)}${pct == null ? '' : ' (${pct > 0 ? '+' : ''}${pct.round()}%)'} · ${yes.length} giorni con, ${no.length} senza.';
    }
    return _correlationText(a, b);
  }

  String _correlationText(_Series a, _Series b, {bool shareLabel = false}) {
    final xs = <double>[], ys = <double>[];
    for (var i = 0; i < a.values.length; i++) {
      final x = a.values[i], y = b.values[i];
      if (x == null || y == null) continue;
      xs.add(x);
      ys.add(y);
    }
    final pa = a.param, pb = b.param;
    final unit = _weekly ? 'settimane' : 'giorni';
    if (xs.length < 5) {
      return '${pa.emoji} ${pa.label} e ${pb.emoji} ${pb.label}: pochi $unit con entrambi i dati (${xs.length}), ne servono almeno 5.';
    }
    final r = _pearson(xs, ys);
    if (r == null) {
      return '${pa.emoji} ${pa.label} e ${pb.emoji} ${pb.label}: uno dei due non cambia mai nel periodo.';
    }
    final strength = r.abs() < 0.2
        ? null
        : r.abs() < 0.4
        ? 'un legame debole'
        : r.abs() < 0.6
        ? 'un legame moderato'
        : 'un legame forte';
    final rText = r.toStringAsFixed(2).replaceAll('.', ',');
    if (strength == null) {
      return '${pa.emoji} ${pa.label} e ${pb.emoji} ${pb.label}: nessun legame chiaro (r = $rText, ${xs.length} $unit).';
    }
    return '${pa.emoji} ${pa.label} e ${pb.emoji} ${pb.label}: $strength — ${r > 0 ? 'quando sale uno tende a salire anche l’altro' : 'quando uno sale l’altro tende a scendere'} (r = $rText, ${xs.length} $unit).';
  }

  static double? _pearson(List<double> x, List<double> y) {
    final n = x.length;
    final mx = x.reduce((a, b) => a + b) / n,
        my = y.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var i = 0; i < n; i++) {
      sxy += (x[i] - mx) * (y[i] - my);
      sxx += (x[i] - mx) * (x[i] - mx);
      syy += (y[i] - my) * (y[i] - my);
    }
    if (sxx == 0 || syy == 0) return null;
    return sxy / math.sqrt(sxx * syy);
  }

  // ---------------------------------------------------------------- grafici

  Widget _legend(List<_Series> series) => Wrap(
    spacing: 14,
    runSpacing: 6,
    children: [
      for (final s in series)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: s.bands ? 14 : 18,
              height: s.bands ? 12 : 3,
              decoration: BoxDecoration(
                color: s.bands ? s.color.withValues(alpha: 0.25) : s.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${s.param.emoji} ${s.param.label}${s.bands ? (s.share ? ' (quota di giorni)' : ' (fascia = fatto)') : ''}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
    ],
  );

  Widget _timeline(List<String> labels, List<_Series> series) {
    final touch = _touch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _legend(series),
        const SizedBox(height: 8),
        SizedBox(
          height: 30,
          child: touch == null || touch >= labels.length
              ? const Text(
                  'Tocca o passa sopra il grafico per leggere i valori di un giorno.',
                  style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                )
              : Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _weekly
                          ? 'Settimana del ${labels[touch]}'
                          : labels[touch],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    for (final s in series)
                      Text(
                        '${s.param.emoji} ${s.bands ? (s.values[touch] == null
                                  ? '—'
                                  : s.share
                                  ? '${(s.values[touch]! * 100).round()}% dei giorni'
                                  : s.values[touch]! > 0.5
                                  ? 'sì'
                                  : 'no') : s.param.format(s.values[touch])}',
                        style: TextStyle(
                          fontSize: 12,
                          color: s.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
        ),
        LayoutBuilder(
          builder: (context, box) {
            void pick(Offset p) {
              const left = 44.0, right = 44.0;
              final w = box.maxWidth - left - right;
              if (labels.isEmpty || w <= 0) return;
              final step = labels.length == 1 ? w : w / (labels.length - 1);
              final i = ((p.dx - left) / step).round().clamp(
                0,
                labels.length - 1,
              );
              if (i != _touch) setState(() => _touch = i);
            }

            return MouseRegion(
              onHover: (e) => pick(e.localPosition),
              child: GestureDetector(
                onTapDown: (d) => pick(d.localPosition),
                onHorizontalDragUpdate: (d) => pick(d.localPosition),
                child: CustomPaint(
                  size: Size(box.maxWidth, 230),
                  painter: _TimelinePainter(labels, series, _touch),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _split(_Series value, _Series flag) {
    final yes = <double>[], no = <double>[];
    for (var i = 0; i < flag.values.length; i++) {
      final f = flag.values[i], v = value.values[i];
      if (f == null || v == null) continue;
      (f > 0.5 ? yes : no).add(v);
    }
    double? mean(List<double> l) =>
        l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
    final my = mean(yes), mn = mean(no);
    final top = math.max(my ?? 0, mn ?? 0);
    Widget column(String title, double? v, int n, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            value.param.format(v),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                width: 70,
                height: v == null || top <= 0
                    ? 4
                    : 130 * (v / top).clamp(0.04, 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Text(
            '$n giorni',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
    return Column(
      children: [
        Text(
          '${value.param.emoji} ${value.param.label} medio',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            column(
              '${flag.param.emoji} Con ${flag.param.label.toLowerCase()}',
              my,
              yes.length,
              flag.color,
            ),
            column(
              'Senza ${flag.param.label.toLowerCase()}',
              mn,
              no.length,
              AppColors.textFaint,
            ),
          ],
        ),
      ],
    );
  }

  Widget _scatter(_Series x, _Series y) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Ogni punto è un ${_weekly ? 'settimana' : 'giorno'}: a destra ${x.param.label} più alto, in alto ${y.param.label} più alto.',
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, box) => CustomPaint(
          size: Size(box.maxWidth, 240),
          painter: _ScatterPainter(x, y),
        ),
      ),
    ],
  );
}

// -------------------------------------------------------------------- pittori

(double, double)? _bounds(Iterable<double> values) {
  if (values.isEmpty) return null;
  var lo = values.reduce(math.min), hi = values.reduce(math.max);
  if (lo == hi) {
    lo -= 1;
    hi += 1;
  }
  final pad = (hi - lo) * 0.1;
  return (lo - pad, hi + pad);
}

void _text(
  Canvas canvas,
  String text,
  Offset at, {
  Color color = AppColors.textMuted,
  double size = 10,
  TextAlign align = TextAlign.left,
  bool bold = false,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = switch (align) {
    TextAlign.right => at.dx - painter.width,
    TextAlign.center => at.dx - painter.width / 2,
    _ => at.dx,
  };
  painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
}

String _short(CompareParam p, double v) {
  if (p.unit == '%' ||
      p.unit == 'passi' ||
      p.unit == 'kcal' ||
      p.unit == 'min') {
    return v.round().toString();
  }
  return v.toStringAsFixed(p.decimals).replaceAll('.', ',');
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.labels, this.series, this.touch);
  final List<String> labels;
  final List<_Series> series;
  final int? touch;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, right = 44.0, top = 8.0, bottom = 22.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final n = labels.length;
    if (n == 0 || plot.width <= 0) return;
    final step = n == 1 ? 0.0 : plot.width / (n - 1);
    double x(int i) => n == 1 ? plot.center.dx : plot.left + step * i;

    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = plot.top + plot.height * g / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }

    // Sì/no: fasce verticali nei giorni «fatto» (o più intense se è una quota).
    for (final s in series.where((s) => s.bands)) {
      final w = math.max(step, 4.0);
      for (var i = 0; i < n; i++) {
        final v = s.values[i];
        if (v == null || v <= 0) continue;
        final alpha = s.share ? 0.08 + 0.3 * v.clamp(0, 1) : 0.18;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x(i) - w / 2, plot.top, x(i) + w / 2, plot.bottom),
            const Radius.circular(3),
          ),
          Paint()..color = s.color.withValues(alpha: alpha.toDouble()),
        );
      }
    }

    var axis = 0;
    for (final s in series.where((s) => !s.bands)) {
      final b = _bounds(s.present);
      if (b == null) continue;
      final (lo, hi) = b;
      double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final v = s.values[i];
        if (v == null) continue;
        final p = Offset(x(i), y(v));
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      if (n <= 60) {
        for (var i = 0; i < n; i++) {
          final v = s.values[i];
          if (v == null) continue;
          canvas.drawCircle(
            Offset(x(i), y(v)),
            touch == i ? 5 : 3,
            Paint()..color = s.color,
          );
          canvas.drawCircle(
            Offset(x(i), y(v)),
            touch == i ? 2.4 : 1.4,
            Paint()..color = Colors.white,
          );
        }
      }
      // Scala propria: la prima serie a sinistra, la seconda a destra.
      if (axis < 2) {
        final ax = axis == 0 ? plot.left - 6 : plot.right + 6;
        final align = axis == 0 ? TextAlign.right : TextAlign.left;
        for (var g = 0; g <= 3; g++) {
          final value = hi - (hi - lo) * g / 3;
          _text(
            canvas,
            _short(s.param, value),
            Offset(ax, plot.top + plot.height * g / 3),
            color: s.color,
            align: align,
          );
        }
      }
      axis++;
    }

    final every = math.max(1, (n / 6).ceil());
    for (var i = 0; i < n; i += every) {
      _text(
        canvas,
        labels[i],
        Offset(x(i), size.height - 9),
        align: TextAlign.center,
      );
    }
    if (touch case final t? when t < n) {
      canvas.drawLine(
        Offset(x(t), plot.top),
        Offset(x(t), plot.bottom),
        Paint()
          ..color = AppColors.text.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.touch != touch || old.series != series || old.labels != labels;
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter(this.xs, this.ys);
  final _Series xs, ys;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, right = 12.0, top = 10.0, bottom = 28.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final points = <(double, double)>[];
    for (var i = 0; i < xs.values.length; i++) {
      final a = xs.values[i], b = ys.values[i];
      if (a != null && b != null) points.add((a, b));
    }
    final border = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(plot, const Radius.circular(8)),
      border,
    );
    if (points.isEmpty) {
      _text(
        canvas,
        'Nessun giorno con entrambi i dati',
        plot.center,
        align: TextAlign.center,
      );
      return;
    }
    final bx = _bounds(points.map((p) => p.$1))!;
    final by = _bounds(points.map((p) => p.$2))!;
    Offset at(double a, double b) => Offset(
      plot.left + (a - bx.$1) / (bx.$2 - bx.$1) * plot.width,
      plot.bottom - (b - by.$1) / (by.$2 - by.$1) * plot.height,
    );
    // Retta di tendenza (minimi quadrati), solo se i punti sono abbastanza.
    if (points.length >= 5) {
      final n = points.length;
      final mx = points.fold(0.0, (s, p) => s + p.$1) / n;
      final my = points.fold(0.0, (s, p) => s + p.$2) / n;
      var sxy = 0.0, sxx = 0.0;
      for (final p in points) {
        sxy += (p.$1 - mx) * (p.$2 - my);
        sxx += (p.$1 - mx) * (p.$1 - mx);
      }
      if (sxx > 0) {
        final slope = sxy / sxx;
        double line(double a) => my + slope * (a - mx);
        canvas.save();
        canvas.clipRect(plot);
        canvas.drawLine(
          at(bx.$1, line(bx.$1)),
          at(bx.$2, line(bx.$2)),
          Paint()
            ..color = ys.color.withValues(alpha: 0.5)
            ..strokeWidth = 2,
        );
        canvas.restore();
      }
    }
    for (final p in points) {
      canvas.drawCircle(
        at(p.$1, p.$2),
        5,
        Paint()..color = xs.color.withValues(alpha: 0.75),
      );
    }
    for (var g = 0; g <= 2; g++) {
      final vy = by.$2 - (by.$2 - by.$1) * g / 2;
      _text(
        canvas,
        _short(ys.param, vy),
        Offset(plot.left - 6, plot.top + plot.height * g / 2),
        color: ys.color,
        align: TextAlign.right,
      );
      final vx = bx.$1 + (bx.$2 - bx.$1) * g / 2;
      _text(
        canvas,
        _short(xs.param, vx),
        Offset(plot.left + plot.width * g / 2, plot.bottom + 9),
        color: xs.color,
        align: TextAlign.center,
      );
    }
    _text(
      canvas,
      '${xs.param.emoji} ${xs.param.label} →',
      Offset(plot.right, size.height - 6),
      color: xs.color,
      align: TextAlign.right,
      bold: true,
    );
    _text(
      canvas,
      '↑ ${ys.param.emoji} ${ys.param.label}',
      Offset(plot.left + 6, plot.top + 8),
      color: ys.color,
      bold: true,
    );
  }

  @override
  bool shouldRepaint(_ScatterPainter old) => old.xs != xs || old.ys != ys;
}
