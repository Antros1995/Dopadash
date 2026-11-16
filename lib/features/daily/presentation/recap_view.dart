import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/presentation/mac_widgets.dart';
import '../../routines/application/routine_controller.dart';
import '../../routines/domain/routine.dart';
import '../../routines/domain/routine_progress.dart';
import '../data/daily_repository.dart';
import '../domain/daily_models.dart';
import 'daily_widgets.dart';
import 'sport_page.dart' show StatTile;
import 'trend_chart.dart';

const recapSections = {'Abitudini', 'Cellulare', 'Sport'};

/// Riepiloghi nel tempo per Statistiche: abitudini e coppe, uso del
/// cellulare, allenamenti e misure del corpo.
class RecapView extends StatefulWidget {
  const RecapView({
    required this.section,
    required this.routines,
    required this.repository,
    this.today,
    super.key,
  });
  final String section;
  final RoutineController routines;
  final DailyRepository repository;
  final DateTime? today;
  @override
  State<RecapView> createState() => _RecapViewState();
}

class _RecapData {
  Map<DateTime, Map<String, RoutineEntry>> entries = {};
  Map<DateTime, int> screen = {}, movement = {};
  List<BodyMeasurement> body = [];
}

class _RecapViewState extends State<RecapView> {
  /// Giorni mostrati; 0 = tutto lo storico.
  int _days = 30;
  DateTime? _firstData;
  BodyMetric _metric = BodyMetric.weight;
  static final _epoch = DateTime(2024);
  _RecapData? _data;
  Object? _error;
  int _request = 0;

  DateTime get _end => dateOnly(widget.today ?? DateTime.now());
  DateTime get _start =>
      _days == 0 ? _firstData ?? _epoch : shiftDays(_end, -(_days - 1));
  int get _span => _end.difference(_start).inDays + 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _data = null;
      _error = null;
      _firstData = null;
    });
    try {
      final data = _RecapData();
      final results = await Future.wait<Object>([
        widget.routines.repository.fetchEntries(
          start: _start,
          endExclusive: shiftDays(_end, 1),
        ),
        // Il cellulare di un giorno entra nel punteggio del giorno dopo.
        widget.repository.fetchScreenTimes(shiftDays(_start, -1), _end),
        widget.repository.fetchMovements(_start, _end),
        widget.repository.loadMeasurements(),
      ]);
      final entries = Map<DateTime, Map<String, RoutineEntry>>.of(
        results[0] as Map<DateTime, Map<String, RoutineEntry>>,
      );
      data
        ..entries = entries
        ..screen = results[1] as Map<DateTime, int>
        ..movement = results[2] as Map<DateTime, int>
        ..body = results[3] as List<BodyMeasurement>;
      if (mounted && request == _request) {
        setState(() {
          _data = data;
          // "Tutto" parte dal primo giorno che ha davvero un dato.
          final days = [...data.entries.keys, ...data.screen.keys];
          _firstData = days.isEmpty
              ? shiftDays(_end, -29)
              : days.reduce((a, b) => a.isBefore(b) ? a : b);
        });
      }
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e);
    }
  }

  /// Le abitudini attive in un giorno; se il server non le ricorda più,
  /// valgono quelle predefinite.
  List<RoutineDefinition> _definitions(DateTime date) {
    final current = [
      for (final r in widget.routines.history)
        if (r.isValidOn(date)) r,
    ];
    return current.isNotEmpty
        ? current
        : [
            for (final r in _defaults)
              if (r.isValidOn(date)) r,
          ];
  }

  static final _defaults = buildDefaultRoutineHistory();

  Iterable<DateTime> get _dates sync* {
    for (var d = _start; !d.isAfter(_end); d = shiftDays(d, 1)) {
      yield d;
    }
  }

  static String shortDay(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  static String hours(num minutes) => formatMinutes(minutes.round());

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: MacSegmented<int>(
            values: const [30, 90, 365, 0],
            selected: _days,
            labelFor: (d) => d == 0
                ? 'Tutto'
                : d == 365
                ? '12 mesi'
                : '$d giorni',
            onSelected: (d) {
              _days = d;
              _load();
            },
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          DailyErrorBanner(onRetry: _load)
        else if (data == null)
          const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          )
        else
          ...switch (widget.section) {
            'Cellulare' => _phone(data),
            'Sport' => _sport(data),
            _ => _habits(data),
          },
      ],
    );
  }

  Widget _tiles(List<(String, String, String, Color)> tiles) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 720 ? 4 : 2;
      final width = (box.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in tiles)
            SizedBox(
              width: width,
              child: StatTile(
                label: t.$1,
                value: t.$2,
                unit: t.$3,
                color: t.$4,
              ),
            ),
        ],
      );
    },
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
    ),
  );

  static Color medalColor(DayMedal medal) => switch (medal) {
    DayMedal.diamond => dailyBlue,
    DayMedal.platinum => dailyPurple,
    DayMedal.gold => const Color(0xFFD99A00),
    DayMedal.silver => const Color(0xFF7C8794),
    DayMedal.bronze => const Color(0xFFB7693A),
    DayMedal.none => AppColors.textFaint,
  };

  // --------------------------------------------------------------- abitudini

  List<Widget> _habits(_RecapData data) {
    final rates = <DateTime, double>{};
    final ok = <String, int>{},
        marked = <String, int>{},
        names = <String, String>{};
    for (final date in _dates) {
      final entries = data.entries[date];
      if (entries == null) continue;
      final definitions = _definitions(date);
      final progress = calculateRoutineProgress(
        definitions: definitions,
        entries: entries,
        effectiveScreenTimeMinutes: data.screen[shiftDays(date, -1)],
      );
      if (!progress.isTracked) continue;
      rates[date] = progress.rate.clamp(0, 1).toDouble();
      for (final r in definitions) {
        final entry = entries[r.id];
        if (entry == null || !entry.isMarked) continue;
        names[r.id] = r.name;
        marked[r.id] = (marked[r.id] ?? 0) + 1;
        if (entry.isCompleted) ok[r.id] = (ok[r.id] ?? 0) + 1;
      }
    }
    if (rates.isEmpty) {
      return [_empty('Nessuna abitudine registrata in questo periodo.')];
    }
    final medals = <DayMedal, int>{};
    for (final rate in rates.values) {
      final m = DayMedal.fromRate(rate);
      medals[m] = (medals[m] ?? 0) + 1;
    }
    final average = rates.values.reduce((a, b) => a + b) / rates.length;
    var streak = 0, best = 0;
    for (final date in _dates) {
      final rate = rates[date];
      streak = rate != null && rate >= .7 ? streak + 1 : 0;
      best = math.max(best, streak);
    }
    final habits = names.keys.toList()
      ..sort(
        (a, b) =>
            (ok[b] ?? 0) / marked[b]! > (ok[a] ?? 0) / marked[a]! ? 1 : -1,
      );
    return [
      _tiles([
        ('Giorni registrati', '${rates.length}', 'su $_span', AppColors.green),
        ('Completamento medio', '${(average * 100).round()}', '%', dailyBlue),
        (
          'Giorni da oro in su',
          '${rates.values.where((r) => r >= .7).length}',
          '',
          const Color(0xFFD99A00),
        ),
        (
          'Serie migliore',
          '$best',
          best == 1 ? 'giorno' : 'giorni',
          dailyPurple,
        ),
      ]),
      const SizedBox(height: 12),
      DailySection(
        icon: Icons.emoji_events_outlined,
        color: const Color(0xFFD99A00),
        title: 'Coppa giorno per giorno',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DayBarsChart(
              height: 150,
              dates: _dates.toList(),
              values: {for (final e in rates.entries) e.key: e.value * 100},
              maximum: 100,
              colorFor: (v) => medalColor(DayMedal.fromRate(v / 100)),
              axisLabel: (v) => '${v.round()}%',
              describe: (v) => v == null
                  ? 'nessuna abitudine registrata'
                  : '${v.round()}% · ${DayMedal.fromRate(v / 100).emoji} ${DayMedal.fromRate(v / 100).label}',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in DayMedal.values.reversed)
                  if (medals[m] != null)
                    MacChip(
                      '${m.emoji} ${m == DayMedal.none ? 'Nessuna' : m.label} · ${medals[m]}',
                      tone: medalColor(m),
                    ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      DailySection(
        icon: Icons.checklist_rounded,
        title: 'Quanto riesci a fare ogni abitudine',
        child: Column(
          children: [
            for (final id in habits)
              _RateRow(
                label: names[id]!,
                done: ok[id] ?? 0,
                total: marked[id]!,
              ),
          ],
        ),
      ),
    ];
  }

  // --------------------------------------------------------------- cellulare

  List<Widget> _phone(_RecapData data) {
    final values = {
      for (final date in _dates)
        if (data.screen[date] != null) date: data.screen[date]!,
    };
    if (values.isEmpty) {
      return [
        _empty('Nessun tempo al cellulare registrato in questo periodo.'),
      ];
    }
    final list = values.values.toList();
    final average = list.reduce((a, b) => a + b) / list.length;
    final best = values.entries.reduce((a, b) => a.value <= b.value ? a : b);
    final half = list.length ~/ 2;
    final trend = half == 0
        ? 0.0
        : list.sublist(half).reduce((a, b) => a + b) / (list.length - half) -
              list.sublist(0, half).reduce((a, b) => a + b) / half;
    final medals = <ScreenTimeMedal, int>{};
    for (final v in list) {
      final m = ScreenTimeMedal.fromMinutes(v);
      medals[m] = (medals[m] ?? 0) + 1;
    }
    Color tone(double minutes) => minutes < 120
        ? AppColors.green
        : minutes < 180
        ? macOrange
        : AppColors.danger;
    return [
      _tiles([
        ('Media al giorno', hours(average), 'ore', tone(average)),
        (
          'Giorno migliore',
          hours(best.value),
          shortDay(best.key),
          AppColors.green,
        ),
        (
          'Giorni sotto le 2 ore',
          '${list.where((v) => v < 120).length}',
          'su ${list.length}',
          dailyBlue,
        ),
        (
          'Tendenza',
          trend.abs() < 3
              ? 'stabile'
              : '${trend < 0 ? '▼' : '▲'} ${hours(trend.abs())}',
          trend.abs() < 3 ? '' : (trend < 0 ? 'in calo' : 'in aumento'),
          trend <= 0 ? AppColors.green : AppColors.danger,
        ),
      ]),
      const SizedBox(height: 12),
      DailySection(
        icon: Icons.smartphone,
        color: dailyBlue,
        title: 'Tempo conteggiato giorno per giorno',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DayBarsChart(
              height: 170,
              dates: _dates.toList(),
              values: {
                for (final e in values.entries) e.key: e.value.toDouble(),
              },
              maximum: math.max(240, list.reduce(math.max).toDouble()),
              colorFor: tone,
              axisLabel: (v) => hours(v),
              guide: 120,
              describe: (v) => v == null
                  ? 'non registrato'
                  : '${hours(v)} conteggiate · ${ScreenTimeMedal.fromMinutes(v.round()).emoji} ${ScreenTimeMedal.fromMinutes(v.round()).label}',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in ScreenTimeMedal.values)
                  if (medals[m] != null)
                    MacChip('${m.emoji} ${m.label} · ${medals[m]}'),
                const MacChip('linea tratteggiata: 2 ore'),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  // ------------------------------------------------------------------- sport

  List<Widget> _sport(_RecapData data) {
    final sessions = <DateTime, double>{};
    final plans = <String, int>{};
    var walks = 0;
    for (final date in _dates) {
      final entries = data.entries[date];
      if (entries == null) continue;
      for (final r in _definitions(date)) {
        final entry = entries[r.id];
        if (entry == null || !entry.isCompleted) continue;
        if (r.iconKey == 'gym') {
          sessions[date] = 1;
          final label =
              r.detailOptions
                  .where((o) => o.id == entry.selectedDetailOptionId)
                  .firstOrNull
                  ?.label ??
              entry.selectedDetailLabelSnapshot ??
              'Senza scheda';
          plans[label] = (plans[label] ?? 0) + 1;
        } else if (r.iconKey == 'walking') {
          walks++;
        }
      }
    }
    final allWeights = [
      for (final m in data.body)
        if (m[_metric] != null) (m.date, m[_metric]!),
    ];
    final inPeriod = [
      for (final w in allWeights)
        if (!w.$1.isBefore(_start)) w,
    ];
    // Le pesate sono rade: se nel periodo ce ne sono meno di due si mostra
    // tutto lo storico, dicendolo.
    final wholeHistory =
        inPeriod.length < 2 && allWeights.length > inPeriod.length;
    final weights = wholeHistory ? allWeights : inPeriod;
    final favourite = plans.entries.isEmpty
        ? null
        : plans.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final weeks = _span / 7;
    String number(double v) => v
        .toStringAsFixed(1)
        .replaceAll(RegExp(r'\.0$'), '')
        .replaceAll('.', ',');
    final total = plans.values.fold(0, (a, b) => a + b);
    return [
      _tiles([
        ('Allenamenti in palestra', '${sessions.length}', '', macOrange),
        (
          'Media a settimana',
          number(sessions.length / weeks),
          'volte',
          dailyBlue,
        ),
        ('Camminate', '$walks', '', AppColors.green),
        (
          'Allenamento più frequente',
          favourite == null ? '—' : favourite.key.split(' – ').first,
          favourite == null ? '' : '${favourite.value} volte',
          dailyPurple,
        ),
      ]),
      const SizedBox(height: 12),
      DailySection(
        icon: Icons.fitness_center,
        color: macOrange,
        title: 'Giorni di palestra',
        child: sessions.isEmpty
            ? _empty('Nessun allenamento segnato in questo periodo.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DayBarsChart(
                    height: 70,
                    dates: _dates.toList(),
                    values: sessions,
                    maximum: 1,
                    colorFor: (_) => macOrange,
                    axisLabel: (_) => '',
                    showAxis: false,
                    describe: (v) =>
                        v == null ? 'nessun allenamento' : 'allenamento fatto',
                  ),
                  const SizedBox(height: 8),
                  for (final plan in plans.keys.toList()..sort())
                    _RateRow(
                      label: plan,
                      done: plans[plan]!,
                      total: total,
                      color: macOrange,
                    ),
                ],
              ),
      ),
      const SizedBox(height: 12),
      DailySection(
        icon: Icons.monitor_weight_outlined,
        title: wholeHistory
            ? 'Peso e misure · tutto lo storico'
            : 'Peso e misure nel periodo',
        status: weights.length >= 2
            ? MacChip(
                '${weights.last.$2 - weights.first.$2 > 0 ? '▲ +' : '▼ −'}${number((weights.last.$2 - weights.first.$2).abs())} ${_metric.unit}',
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final metric in BodyMetric.values)
                  ChoicePill(
                    label: metric.label,
                    selected: metric == _metric,
                    onTap: () => setState(() => _metric = metric),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (wholeHistory)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Nel periodo scelto ci sono meno di due misure: ecco tutte quelle registrate.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            if (weights.isEmpty)
              _empty(
                'Nessuna misura di ${_metric.label.toLowerCase()} registrata. Aggiungila dalla scheda Sport.',
              )
            else
              TrendChart(points: weights, unit: _metric.unit, height: 210),
          ],
        ),
      ),
    ];
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.label,
    required this.done,
    required this.total,
    this.color = AppColors.green,
  });
  final String label;
  final int done, total;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final rate = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, color: AppColors.text),
            ),
          ),
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 8,
                backgroundColor: AppColors.fill,
                color: color,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              '${(rate * 100).round()}% · $done/$total',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre giornaliere interattive: passando il mouse o toccando un giorno si
/// legge sotto la data con il suo valore.
class DayBarsChart extends StatefulWidget {
  const DayBarsChart({
    required this.dates,
    required this.values,
    required this.maximum,
    required this.colorFor,
    required this.axisLabel,
    required this.describe,
    this.guide,
    this.showAxis = true,
    this.height = 150,
    super.key,
  });
  final List<DateTime> dates;
  final Map<DateTime, double> values;
  final double maximum, height;
  final Color Function(double) colorFor;
  final String Function(double) axisLabel;

  /// Testo del valore di un giorno (null = nessun dato).
  final String Function(double?) describe;
  final double? guide;
  final bool showAxis;
  @override
  State<DayBarsChart> createState() => _DayBarsChartState();
}

class _DayBarsChartState extends State<DayBarsChart> {
  int? _hover;

  void _point(Offset local, double width) {
    final left = widget.showAxis ? 40.0 : 0.0;
    final slot = (width - left) / widget.dates.length;
    final i = ((local.dx - left) / slot).floor();
    final next = i >= 0 && i < widget.dates.length ? i : null;
    if (next != _hover) setState(() => _hover = next);
  }

  @override
  Widget build(BuildContext context) {
    final hover = _hover != null && _hover! < widget.dates.length
        ? _hover
        : null;
    final date = hover == null ? null : widget.dates[hover];
    String two(int n) => n.toString().padLeft(2, '0');
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
                  painter: DayBarsPainter(
                    dates: widget.dates,
                    values: widget.values,
                    maximum: widget.maximum,
                    colorFor: widget.colorFor,
                    axisLabel: widget.axisLabel,
                    guide: widget.guide,
                    showAxis: widget.showAxis,
                    hover: hover,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          date == null
              ? 'Tocca o passa su una barra per leggere il valore del giorno.'
              : '${two(date.day)}/${two(date.month)}/${date.year} · ${widget.describe(widget.values[date])}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: date == null ? FontWeight.w400 : FontWeight.w600,
            color: date == null ? AppColors.textMuted : AppColors.text,
          ),
        ),
      ],
    );
  }
}

/// Una barra per giorno; i giorni senza dato restano vuoti.
class DayBarsPainter extends CustomPainter {
  DayBarsPainter({
    this.hover,
    required this.dates,
    required this.values,
    required this.maximum,
    required this.colorFor,
    required this.axisLabel,
    this.guide,
    this.showAxis = true,
  });
  final List<DateTime> dates;
  final Map<DateTime, double> values;
  final double maximum;
  final Color Function(double) colorFor;
  final String Function(double) axisLabel;
  final double? guide;
  final bool showAxis;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final left = showAxis ? 40.0 : 0.0;
    const bottom = 18.0, top = 4.0;
    final plot = Rect.fromLTRB(left, top, size.width, size.height - bottom);
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
    if (showAxis) {
      for (var i = 0; i <= 2; i++) {
        final y = plot.top + plot.height * i / 2;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
        text(axisLabel(maximum * (1 - i / 2)), Offset(0, y - 6));
      }
    } else {
      canvas.drawLine(plot.bottomLeft, plot.bottomRight, grid);
    }
    final slot = plot.width / dates.length;
    final bar = math.max(1.5, math.min(14.0, slot * .72));
    if (hover != null) {
      canvas.drawRect(
        Rect.fromLTWH(plot.left + slot * hover!, plot.top, slot, plot.height),
        Paint()..color = AppColors.fill,
      );
    }
    for (var i = 0; i < dates.length; i++) {
      final value = values[dates[i]];
      if (value == null) continue;
      final h = math.max(2.0, plot.height * (value / maximum).clamp(0, 1));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            plot.left + slot * i + (slot - bar) / 2,
            plot.bottom - h,
            bar,
            h,
          ),
          Radius.circular(math.min(3, bar / 2)),
        ),
        Paint()..color = colorFor(value),
      );
    }
    if (guide != null && guide! < maximum) {
      final y = plot.bottom - plot.height * guide! / maximum;
      final dash = Paint()
        ..color = AppColors.textMuted
        ..strokeWidth = 1;
      for (var x = plot.left; x < plot.right; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, plot.right), y),
          dash,
        );
      }
    }
    String day(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    text(day(dates.first), Offset(plot.left, plot.bottom + 4));
    text(day(dates.last), Offset(plot.right, plot.bottom + 4), right: true);
  }

  @override
  bool shouldRepaint(DayBarsPainter old) =>
      old.hover != hover ||
      old.values != values ||
      old.dates.length != dates.length;
}
