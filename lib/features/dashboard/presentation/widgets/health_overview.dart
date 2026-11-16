import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../app/theme.dart';
import '../../../../core/presentation/app_card.dart';
import '../../../../core/presentation/responsive_layout.dart';
import '../../../../core/utils/external_url_launcher.dart';
import '../../../fitbit/application/fitbit_controller.dart';
import '../../../fitbit/domain/fitbit_day.dart';
import '../health_presentation.dart';
import 'home_components.dart';

const _purple = Color(0xFF7956EF);
const _blue = Color(0xFF28A4EB);
const _pink = Color(0xFFE45FA7);

class HealthOverview extends StatelessWidget {
  const HealthOverview({
    required this.controller,
    required this.isToday,
    this.panel,
    super.key,
  });
  final FitbitController controller;
  final bool isToday;
  final String? panel;
  Future<void> _connect(BuildContext context) async {
    try {
      final url = await controller.beginConnect();
      await launchExternalUrl(url);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Collegamento Fitbit non disponibile. Riprova.'),
          ),
        );
      }
    }
  }

  Future<void> _mindfulness(BuildContext context) async {
    final text = TextEditingController(
      text: controller.day?.mindfulnessMinutes?.toString() ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Minuti di mindfulness'),
        content: TextField(
          controller: text,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Inserimento manuale · minuti',
            helperText: 'Lascia vuoto per rimuovere il dato.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              final raw = text.text.trim();
              final value = int.tryParse(raw);
              if (raw.isEmpty ||
                  (value != null && value >= 0 && value <= 1440)) {
                Navigator.pop(context, raw);
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    // The closing dialog still owns its editable during the reverse animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    text.dispose();
    if (result != null) {
      try {
        await controller.saveMindfulnessMinutes(
          result.isEmpty ? null : int.parse(result),
        );
      } on Object {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Minuti non salvati. Riprova.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = controller.day;
    if (day == null) {
      return AppCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeHeading(
              title: 'Salute',
              icon: Icons.favorite_outline,
              action: IconButton(
                tooltip: 'Aggiorna dati salute',
                onPressed: controller.isLoading ? null : controller.load,
                icon: const Icon(Icons.refresh, size: 19),
              ),
            ),
            const SizedBox(height: 18),
            if (controller.isLoading)
              const LinearProgressIndicator()
            else if (controller.failure != null)
              const Text(
                'Non è stato possibile caricare i dati salute. Riprova con Aggiorna.',
              )
            else
              Text(
                !controller.isConfigured
                    ? 'Integrazione salute non configurata.'
                    : controller.isConnected
                    ? 'Nessun dato salute disponibile per questa giornata.'
                    : 'Collega Fitbit per visualizzare i tuoi dati salute.',
              ),
            if (controller.isConfigured &&
                !controller.isConnected &&
                !controller.isLoading &&
                controller.failure == null)
              TextButton.icon(
                onPressed: () => _connect(context),
                icon: const Icon(Icons.link),
                label: const Text('Collega Fitbit'),
              ),
          ],
        ),
      );
    }
    final presentation = HealthPresentation(day, isToday: isToday);
    if (panel == 'sleep') return _SleepCard(day: day, model: presentation);
    if (panel == 'body') return _BodyCard(model: presentation);
    if (panel == 'insight') {
      return _InsightCard(model: presentation, isToday: isToday);
    }
    if (panel == 'metrics') {
      return _MetricStrip(
        day: day,
        isToday: isToday,
        onRefresh: controller.isLoading ? null : controller.load,
        onMindfulness: () => _mindfulness(context),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.failure != null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Aggiornamento non riuscito: sono mostrati gli ultimi dati ricevuti.',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ),
        LayoutBuilder(
          builder: (context, box) {
            final sleep = _SleepCard(day: day, model: presentation);
            final body = _BodyCard(model: presentation);
            final insight = _InsightCard(model: presentation, isToday: isToday);
            if (box.maxWidth >= 1050) {
              return SizedBox(
                height: 282,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 40, child: sleep),
                    const SizedBox(width: 12),
                    Expanded(flex: 29, child: body),
                    const SizedBox(width: 12),
                    Expanded(flex: 31, child: insight),
                  ],
                ),
              );
            }
            if (box.maxWidth >= 650) {
              return Column(
                children: [
                  SizedBox(height: 282, child: sleep),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 270,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: body),
                        const SizedBox(width: 12),
                        Expanded(child: insight),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                SizedBox(height: 310, child: sleep),
                const SizedBox(height: 12),
                SizedBox(height: 270, child: body),
                const SizedBox(height: 12),
                SizedBox(height: 260, child: insight),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _MetricStrip(
          day: day,
          isToday: isToday,
          onRefresh: controller.isLoading ? null : controller.load,
          onMindfulness: () => _mindfulness(context),
        ),
      ],
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.day, required this.model});
  final FitbitDay day;
  final HealthPresentation model;
  @override
  Widget build(BuildContext context) {
    final minutes = day.sleepMinutes;
    final deep = day.sleepDetails?.stageMinutes.deep;
    final score = model.sleepScore;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeading(
            title: 'Sonno',
            icon: Icons.nights_stay_outlined,
            color: _purple,
            action: HomeLink(
              label: 'Dettagli ›',
              onTap: () => _showHealthDetails(context, day),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            // Sul telefono i tre valori vanno su due righe.
            height: usesPhoneLayout(context) ? 106 : 91,
            child: Row(
              children: [
                if (score != null) ...[
                  Tooltip(
                    message:
                        'Indice dell’app: durata rispetto a 8 ore (70%) + efficienza (30%). Non è lo Sleep Score Fitbit.',
                    child: HomeRing(
                      value: score.toDouble(),
                      label: 'Indice app',
                      color: _purple,
                      size: 88,
                    ),
                  ),
                  const SizedBox(width: 18),
                ],
                Expanded(
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 6,
                    children: [
                      if (HealthPresentation.positive(minutes))
                        _Fact(
                          value: durationLabel(minutes!),
                          label: 'Tempo totale',
                        ),
                      if (HealthPresentation.positive(day.sleepEfficiency) &&
                          day.sleepEfficiency! <= 100)
                        _Fact(
                          value: '${day.sleepEfficiency}%',
                          label: 'Efficienza',
                        ),
                      if (HealthPresentation.positive(deep))
                        _Fact(
                          value: durationLabel(deep!),
                          label: 'Sonno profondo',
                        ),
                      if (!HealthPresentation.positive(minutes))
                        const Text(
                          'Nessuna durata registrata.',
                          style: TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SleepHypnogram(
              stages: day.sleepStages,
              details: day.sleepDetails,
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class _BodyCard extends StatelessWidget {
  const _BodyCard({required this.model});
  final HealthPresentation model;
  @override
  Widget build(BuildContext context) {
    final recovery = model.recovery;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeHeading(title: 'Stato del corpo', icon: Icons.spa_outlined),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                if (recovery != null)
                  HomeRing(
                    value: recovery.toDouble(),
                    label: 'Recupero',
                    color: AppColors.green,
                    size: 106,
                  )
                else
                  Container(
                    width: 94,
                    height: 94,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.greenSoft, width: 10),
                    ),
                    child: const Icon(
                      Icons.spa_outlined,
                      size: 32,
                      color: AppColors.green,
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    recovery == null
                        ? 'Dati parziali.\nIl recupero non è stimabile per questa giornata.'
                        : 'Stima dell’app\nsu sonno e segnali cardiaci disponibili.',
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (model.sleepScore != null)
            _SignalBar(
              label: 'Sonno',
              value: model.sleepScore! / 100,
              text: '${model.sleepScore}',
              color: AppColors.green,
            ),
          if (recovery != null)
            _SignalBar(
              label: 'Recupero',
              value: recovery / 100,
              text: '$recovery',
              color: const Color(0xFF69CF79),
            ),
          if (model.load != null)
            _SignalBar(
              label: 'Carico',
              value: model.load! / 21,
              text: '${model.load!.toStringAsFixed(1)}/21',
              color: const Color(0xFFFFBD23),
            ),
          const SizedBox(height: 5),
          Tooltip(
            message:
                'Sono mantenute le formule preesistenti dell’app. Recupero: media pesata di sonno, HRV e FC a riposo; carico: trasformazione logaritmica dei minuti nelle zone. Non sono punteggi ufficiali Fitbit né valutazioni cliniche.',
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 12, color: AppColors.textMuted),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Indici app · metodo e limiti',
                    style: TextStyle(fontSize: 10),
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

class _SignalBar extends StatelessWidget {
  const _SignalBar({
    required this.label,
    required this.value,
    required this.text,
    required this.color,
  });
  final String label, text;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value.clamp(0, 1),
              minHeight: 10,
              backgroundColor: const Color(0xFFF0F4F3),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.model, required this.isToday});
  final HealthPresentation model;
  final bool isToday;
  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeHeading(
          title: isToday ? 'Insight di oggi' : 'Insight del giorno',
          icon: Icons.auto_awesome_outlined,
          color: const Color(0xFF38B85D),
        ),
        const SizedBox(height: 15),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (model.insights.isEmpty)
                  const Text(
                    'Dati insufficienti per formulare un insight.',
                    style: TextStyle(fontSize: 13, height: 1.6),
                  )
                else
                  for (final insight in model.insights)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Text(
                        insight,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.text,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const Divider(),
        const SizedBox(height: 9),
        Text(
          isToday
              ? 'I campioni ricevuti non hanno date e possono includere oggi. Nessun confronto su finestre temporali presunte.'
              : 'Giornata storica: nessun confronto con trend privi di data.',
          style: const TextStyle(fontSize: 10, height: 1.4),
        ),
      ],
    ),
  );
}

class _Metric {
  const _Metric(
    this.name,
    this.value,
    this.unit,
    this.caption,
    this.icon,
    this.color,
    this.trend, {
    this.bars = false,
  });
  final String name, value, unit, caption;
  final IconData icon;
  final Color color;
  final List<double> trend;
  final bool bars;
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({
    required this.day,
    required this.isToday,
    required this.onRefresh,
    required this.onMindfulness,
  });
  final FitbitDay day;
  final bool isToday;
  final VoidCallback? onRefresh;
  final VoidCallback onMindfulness;
  List<_Metric> get metrics {
    bool valid(num? value) => HealthPresentation.positive(value);
    final sample = isToday ? day.latestHeartRate : null;
    FitbitHeartPoint? latestInterval;
    if (isToday && sample == null) {
      for (final point in day.heartProfile) {
        if (valid(point.average) &&
            (latestInterval == null ||
                point.startTime.isAfter(latestInterval.startTime))) {
          latestInterval = point;
        }
      }
    }
    return [
      if (sample != null)
        _Metric(
          'Ultimo battito',
          '${sample.beatsPerMinute}',
          'bpm',
          'Misurato alle ${_time(sample.measuredAt)}',
          Icons.favorite_outline,
          _pink,
          const [],
        )
      else if (latestInterval != null)
        _Metric(
          'FC media',
          latestInterval.average.toStringAsFixed(0),
          'bpm',
          '${_time(latestInterval.startTime)}–'
              '${_time(latestInterval.startTime.add(const Duration(minutes: 30)))}',
          Icons.favorite_outline,
          _pink,
          const [],
        ),
      if (valid(day.restingHeartRate))
        _Metric(
          'FC a riposo',
          '${day.restingHeartRate}',
          'bpm',
          'Giornaliera',
          Icons.favorite_outline,
          _pink,
          day.restingHeartRateTrend,
        ),
      if (valid(day.heartRateVariabilityMs))
        _Metric(
          'HRV',
          day.heartRateVariabilityMs!.toStringAsFixed(0),
          'ms',
          'Notturna',
          Icons.monitor_heart_outlined,
          const Color(0xFF13BBD0),
          day.heartRateVariabilityTrend,
        ),
      if (valid(day.oxygenSaturation?.average) &&
          day.oxygenSaturation!.average <= 100)
        _Metric(
          'SpO₂',
          day.oxygenSaturation!.average.toStringAsFixed(0),
          '%',
          'Media notturna',
          Icons.water_drop_outlined,
          _blue,
          day.oxygenSaturationTrend,
          bars: true,
        ),
      if (valid(day.respiratoryRate))
        _Metric(
          'Respirazione',
          day.respiratoryRate!.toStringAsFixed(0),
          '/min',
          'Media notturna',
          Icons.air,
          const Color(0xFF439CC0),
          day.respiratoryRateTrend,
        ),
      if (day.steps > 0)
        _Metric(
          'Passi',
          _integer(day.steps),
          '',
          'Registrati',
          Icons.directions_walk,
          AppColors.green,
          day.stepsTrend,
          bars: true,
        ),
      if (valid(day.distanceKm))
        _Metric(
          'Distanza',
          day.distanceKm.toStringAsFixed(1),
          'km',
          'Percorsa',
          Icons.route_outlined,
          const Color(0xFF29AE89),
          day.distanceTrend,
          bars: true,
        ),
      if (day.calories > 0)
        _Metric(
          'Calorie',
          _integer(day.calories),
          'kcal',
          'Totali',
          Icons.local_fire_department_outlined,
          const Color(0xFFFFA408),
          day.caloriesTrend,
          bars: true,
        ),
      if (valid(day.activeZoneMinutes))
        _Metric(
          'Zone attive',
          '${day.activeZoneMinutes}',
          'min',
          'Registrate',
          Icons.bolt,
          _pink,
          day.activeZoneMinutesTrend,
          bars: true,
        )
      else if (day.activeMinutes > 0)
        _Metric(
          'Attività',
          '${day.activeMinutes}',
          'min',
          'Minuti attivi',
          Icons.bolt,
          _pink,
          day.activeMinutesTrend,
          bars: true,
        ),
      if (day.workouts.isNotEmpty)
        _Metric(
          'Workout',
          '${day.workouts.length}',
          '',
          'Nel giorno',
          Icons.fitness_center,
          _purple,
          const [],
        ),
      if (valid(day.vo2Max?.value))
        _Metric(
          'VO₂ max',
          day.vo2Max!.value.toStringAsFixed(1),
          '',
          day.vo2Max!.measuredDate,
          Icons.speed,
          const Color(0xFF478DCA),
          day.vo2MaxTrend,
        ),
      if (valid(day.skinTemperature?.nightlyCelsius))
        _Metric(
          'Temperatura',
          day.skinTemperature!.nightlyCelsius.toStringAsFixed(1),
          '°C',
          'Cutanea notturna',
          Icons.thermostat,
          const Color(0xFFDF9061),
          day.skinTemperatureTrend,
        ),
      if (valid(day.mindfulnessMinutes))
        _Metric(
          'Mindfulness',
          '${day.mindfulnessMinutes}',
          'min',
          'Inserita a mano',
          Icons.self_improvement,
          AppColors.green,
          const [],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = metrics;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeading(
            title: 'I tuoi parametri di salute',
            icon: Icons.favorite,
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Ultimo aggiornamento: ${day.syncedAt.toLocal()}',
                  child: const Icon(
                    Icons.schedule,
                    size: 15,
                    color: AppColors.textMuted,
                  ),
                ),
                IconButton(
                  tooltip: 'Aggiorna dati salute',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Dettagli e dati manuali',
                  onSelected: (action) => action == 'details'
                      ? _showHealthDetails(context, day)
                      : onMindfulness(),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'details',
                      child: Text('Dettagli salute e allenamenti'),
                    ),
                    const PopupMenuItem(
                      value: 'mindfulness',
                      child: Text('Inserisci minuti mindfulness'),
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz, size: 18),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nessun parametro valido per questa giornata.',
                style: TextStyle(fontSize: 12),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, box) {
                final columns = math.min(
                  items.length,
                  math.max(1, (box.maxWidth / 116).floor()),
                );
                final width = (box.maxWidth - (columns - 1) * 7) / columns;
                return Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final metric in items)
                      SizedBox(
                        width: width,
                        height: 117,
                        child: _MetricTile(metric: metric),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

String _integer(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]}.',
);

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});
  final _Metric metric;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(metric.icon, size: 14, color: metric.color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                metric.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: metric.value,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' ${metric.unit}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            style: const TextStyle(color: AppColors.text),
          ),
        ),
        Text(
          metric.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10),
        ),
        const Spacer(),
        if (metric.trend.where((n) => n.isFinite).length >= 2)
          Tooltip(
            message: 'Campioni disponibili, senza date associate.',
            child: SizedBox(
              height: 25,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparkPainter(metric.trend, metric.color, metric.bars),
              ),
            ),
          ),
      ],
    ),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.bars);
  final List<double> values;
  final Color color;
  final bool bars;
  @override
  void paint(Canvas canvas, Size size) {
    final data = values.where((v) => v.isFinite && v >= 0).toList();
    if (data.length < 2) return;
    final low = bars ? 0.0 : data.reduce(math.min);
    final high = data.reduce(math.max);
    final range = high == low ? 1.0 : high - low;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    if (bars) {
      paint.style = PaintingStyle.fill;
      final w = size.width / data.length;
      for (var i = 0; i < data.length; i++) {
        final h = (data[i] - low) / range * (size.height - 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(i * w, size.height - h, w * .68, h),
            const Radius.circular(1),
          ),
          paint,
        );
      }
    } else {
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final x = i / (data.length - 1) * size.width;
        final y = high == low
            ? size.height / 2
            : size.height - 2 - (data[i] - low) / range * (size.height - 4);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      values != old.values || color != old.color || bars != old.bars;
}

class SleepHypnogram extends StatelessWidget {
  const SleepHypnogram({
    required this.stages,
    required this.details,
    super.key,
  });
  final List<FitbitSleepStage> stages;
  final FitbitSleepDetails? details;
  @override
  Widget build(BuildContext context) {
    final valid = stages.where((s) => s.endTime.isAfter(s.startTime)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (valid.isEmpty) {
      return const Center(
        child: Text(
          'Le fasi temporali della notte non sono disponibili.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
      );
    }
    final start = valid.first.startTime;
    final end = valid
        .map((s) => s.endTime)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return Semantics(
      label:
          'Ipnogramma: ${valid.length} intervalli registrati, dalle ${_time(start)} alle ${_time(end)}. Le fasi non classificate restano vuote.',
      child: CustomPaint(
        key: const ValueKey('fitbit-sleep-timeline'),
        painter: _HypnogramPainter(
          valid,
          start,
          end,
          Theme.of(context).textTheme.bodySmall?.color ?? AppColors.textMuted,
        ),
        size: Size.infinite,
      ),
    );
  }
}

String _time(DateTime t) {
  final local = t.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _HypnogramPainter extends CustomPainter {
  _HypnogramPainter(this.stages, this.start, this.end, this.textColor);
  final List<FitbitSleepStage> stages;
  final DateTime start, end;
  final Color textColor;
  static const labels = ['Sveglio', 'REM', 'Leggero', 'Profondo'];
  static const colors = [
    Color(0xFFF071BD),
    Color(0xFFB063EF),
    Color(0xFF5EADFF),
    Color(0xFF5263F5),
  ];
  int? lane(String type) => switch (type.toLowerCase()) {
    'wake' || 'awake' => 0,
    'rem' => 1,
    'light' => 2,
    'deep' => 3,
    _ => null,
  };
  void text(Canvas c, String s, Offset p, {double width = 55}) {
    final t = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: textColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    t.paint(c, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 59.0;
    // A browser viewport change can briefly paint a collapsed card.
    // There must be room for the label gutter and the time-axis labels.
    if (size.width < 100 || size.height < 40) return;
    final width = math.max(0.0, size.width - left - 4);
    final height = math.max(4.0, size.height - 23);
    final row = height / 4;
    final duration = end.difference(start).inMilliseconds;
    if (duration <= 0) return;
    double x(DateTime time) =>
        left + time.difference(start).inMilliseconds / duration * width;
    final grid = Paint()
      ..color = const Color(0xFFE9E9ED)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      canvas.drawLine(Offset(left, i * row), Offset(size.width, i * row), grid);
      if (i < 4) text(canvas, labels[i], Offset(0, i * row + 2));
    }
    for (var i = 0; i <= 4; i++) {
      final px = left + width * i / 4;
      canvas.drawLine(Offset(px, 0), Offset(px, height), grid);
      final t = start.add(Duration(milliseconds: (duration * i / 4).round()));
      text(
        canvas,
        _time(t),
        Offset((px - 13).clamp(left - 13, size.width - 32), height + 6),
        width: 38,
      );
    }
    FitbitSleepStage? previous;
    int? previousLane;
    for (final stage in stages) {
      final l = lane(stage.type);
      if (l == null) {
        previous = null;
        previousLane = null;
        continue;
      }
      final y = l * row + 2;
      final paint = Paint()..color = colors[l];
      canvas.drawRect(
        Rect.fromLTWH(
          x(stage.startTime),
          y,
          math.max(1, x(stage.endTime) - x(stage.startTime)),
          math.max(2, row - 3),
        ),
        paint,
      );
      if (previous != null &&
          previous.endTime == stage.startTime &&
          previousLane != null) {
        canvas.drawLine(
          Offset(x(stage.startTime), previousLane * row + row / 2),
          Offset(x(stage.startTime), y + row / 2),
          Paint()
            ..color = colors[l].withValues(alpha: .5)
            ..strokeWidth = 1,
        );
      }
      previous = stage;
      previousLane = l;
    }
  }

  @override
  bool shouldRepaint(_HypnogramPainter old) =>
      stages != old.stages || start != old.start || end != old.end;
}

void _showHealthDetails(BuildContext context, FitbitDay day) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 860,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HomeHeading(
                title: 'Salute · ${day.date}',
                icon: Icons.favorite_outline,
                action: IconButton(
                  tooltip: 'Chiudi',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Fitbit / Google Health · aggiornato ${day.syncedAt.toLocal()}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (day.sleepStages.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'La notte, fase per fase',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 180,
                          child: SleepHypnogram(
                            stages: day.sleepStages,
                            details: day.sleepDetails,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          title: const Text(
                            'Intervalli registrati',
                            style: TextStyle(fontSize: 13),
                          ),
                          children: [
                            for (final stage in day.sleepStages.where(
                              (s) => s.endTime.isAfter(s.startTime),
                            ))
                              ListTile(
                                dense: true,
                                title: Text(
                                  '${_time(stage.startTime)} – ${_time(stage.endTime)}',
                                ),
                                subtitle: Text(_stageName(stage.type)),
                                trailing: Text(
                                  '${stage.endTime.difference(stage.startTime).inMinutes} min',
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (day.sleepDetails != null) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          children: [
                            if (day.sleepDetails!.stageMinutes.rem > 0)
                              _Fact(
                                value: durationLabel(
                                  day.sleepDetails!.stageMinutes.rem,
                                ),
                                label: 'REM',
                              ),
                            if (day.sleepDetails!.stageMinutes.light > 0)
                              _Fact(
                                value: durationLabel(
                                  day.sleepDetails!.stageMinutes.light,
                                ),
                                label: 'Leggero',
                              ),
                            if (day.sleepDetails!.stageMinutes.deep > 0)
                              _Fact(
                                value: durationLabel(
                                  day.sleepDetails!.stageMinutes.deep,
                                ),
                                label: 'Profondo',
                              ),
                            if (day.sleepDetails!.minutesAwake > 0)
                              _Fact(
                                value: '${day.sleepDetails!.minutesAwake} min',
                                label: 'Sveglio',
                              ),
                          ],
                        ),
                      ],
                      if (day.heartProfile.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Frequenza cardiaca · profilo del giorno',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 160,
                          child: CustomPaint(
                            painter: _HeartTimeline(day.heartProfile),
                          ),
                        ),
                      ],
                      if (HealthPresentation.positive(
                        day.sedentaryMinutes,
                      )) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Tempo sedentario rilevato: ${durationLabel(day.sedentaryMinutes!)}',
                        ),
                      ],
                      if (day.workouts.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Allenamenti registrati',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        for (final workout in day.workouts)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.fitness_center,
                              color: _purple,
                            ),
                            title: Text(workout.name ?? workout.type),
                            subtitle: Text(
                              '${_time(workout.startTime)} · ${workout.activeMinutes} min${workout.averageHeartRate == null ? '' : ' · FC media ${workout.averageHeartRate} bpm'}${workout.distanceKm == null ? '' : ' · ${workout.distanceKm!.toStringAsFixed(2)} km'}${workout.calories == null ? '' : ' · ${workout.calories} kcal'}',
                            ),
                          ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        day.finalized
                            ? 'Giornata conclusa · dato archiviato'
                            : 'Giornata in corso · dati in aggiornamento',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _stageName(String type) => switch (type.toLowerCase()) {
  'awake' || 'wake' => 'Sveglio',
  'rem' => 'REM',
  'light' => 'Leggero',
  'deep' => 'Profondo',
  'asleep' => 'Sonno non classificato',
  'restless' => 'Agitato',
  _ => 'Fase non classificata ($type)',
};

class _HeartTimeline extends CustomPainter {
  _HeartTimeline(this.source);
  final List<FitbitHeartPoint> source;
  @override
  void paint(Canvas canvas, Size size) {
    final points =
        source.where((p) => p.average.isFinite && p.average > 0).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (points.isEmpty) return;
    final low = points.map((p) => p.average).reduce(math.min) - 5;
    final high = points.map((p) => p.average).reduce(math.max) + 5;
    final span = points.last.startTime
        .difference(points.first.startTime)
        .inMilliseconds;
    double x(FitbitHeartPoint p) => span == 0
        ? size.width / 2
        : (p.startTime.difference(points.first.startTime).inMilliseconds /
                      span) *
                  (size.width - 42) +
              34;
    double y(double value) =>
        6 + (high - value) / (high - low) * (size.height - 30);
    final pen = Paint()
      ..color = _pink
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (i == 0) {
        path.moveTo(x(p), y(p.average));
      } else {
        path.lineTo(x(p), y(p.average));
      }
    }
    canvas.drawPath(path, pen);
    if (points.length == 1) {
      canvas.drawCircle(
        Offset(x(points.first), y(points.first.average)),
        3,
        Paint()..color = _pink,
      );
    }
    void label(String value, Offset point) {
      final t = TextPainter(
        text: TextSpan(
          text: value,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(canvas, point);
    }

    label('${high.round()} bpm', Offset.zero);
    label('${low.round()}', Offset(0, size.height - 30));
    label(_time(points.first.startTime), Offset(34, size.height - 14));
    label(
      _time(points.last.startTime),
      Offset(size.width - 36, size.height - 14),
    );
  }

  @override
  bool shouldRepaint(_HeartTimeline old) => source != old.source;
}
