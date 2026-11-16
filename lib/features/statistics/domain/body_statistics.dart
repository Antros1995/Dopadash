import 'dart:math' as math;
import 'perception_statistics.dart';

// Calendar dates are UTC labels, not instants: DST must not change day counts.
DateTime statsDate(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);
String statsKey(DateTime date) => date.toIso8601String().substring(0, 10);
DateTime statsParse(String value) => statsDate(DateTime.parse(value));

/// EU daylight saving transitions occur at 01:00 UTC on the last Sunday.
DateTime romeWallTime(DateTime instant) {
  final utc = instant.toUtc();
  DateTime transition(int month) {
    final last = DateTime.utc(utc.year, month + 1, 0, 1);
    return last.subtract(Duration(days: last.weekday % 7));
  }

  final summer = !utc.isBefore(transition(3)) && utc.isBefore(transition(10));
  return utc.add(Duration(hours: summer ? 2 : 1));
}

enum BodyPeriod {
  day('24 ore', 1),
  week('7 giorni', 7),
  month('1 mese', 30),
  quarter('3 mesi', 90),
  year('1 anno', 365),
  all('Tutto', null),
  custom('Personalizzato', null);

  const BodyPeriod(this.label, this.days);
  final String label;
  final int? days;
}

class BodyRange {
  BodyRange(DateTime start, DateTime end)
    : start = statsDate(start),
      end = statsDate(end) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('Intervallo non valido');
    }
  }
  final DateTime start, end;
  int get days => end.difference(start).inDays + 1;
  bool contains(DateTime day) =>
      !statsDate(day).isBefore(start) && !statsDate(day).isAfter(end);
  Iterable<DateTime> get dates sync* {
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      yield d;
    }
  }

  BodyRange get previous => BodyRange(
    start.subtract(Duration(days: days)),
    start.subtract(const Duration(days: 1)),
  );
  Map<String, Object?> toJson() => {
    'start': statsKey(start),
    'end': statsKey(end),
  };
  factory BodyRange.fromJson(Map<String, dynamic> json) => BodyRange(
    statsParse(json['start'] as String),
    statsParse(json['end'] as String),
  );
}

enum BodyMetric {
  sleep('sleepMinutes', 'Durata del sonno', 'min'),
  efficiency('sleepEfficiency', 'Efficienza del sonno', '%'),
  restingHr('restingHeartRate', 'FC a riposo', 'bpm'),
  hrv('heartRateVariabilityMs', 'HRV notturna', 'ms'),
  steps('steps', 'Passi', 'passi'),
  distance('distanceKm', 'Distanza', 'km'),
  active('activeMinutes', 'Minuti attivi', 'min'),
  calm('calm', 'Calma percepita', '/5'),
  stress('stress', 'Stress percepito', '/10');

  const BodyMetric(this.key, this.label, this.unit);
  final String key, label, unit;
  bool get manual => this == stress;
  bool get perception => this == calm;
  static BodyMetric parse(String key) => values.firstWhere((m) => m.key == key);
  String format(double? value, {bool delta = false}) {
    if (value == null || !value.isFinite) return '—';
    final sign = delta && value > 0 ? '+' : '';
    if (this == sleep && !delta) {
      final minutes = value.round();
      return '${minutes ~/ 60} h ${minutes % 60} min';
    }
    final decimals = this == distance || manual || perception ? 1 : 0;
    final number = value.toStringAsFixed(decimals).replaceAll('.', ',');
    final suffix = delta && (manual || perception || this == efficiency)
        ? 'punti'
        : unit;
    return '$sign$number $suffix';
  }
}

class BodyDay {
  BodyDay(Map<String, dynamic> data)
    : data = Map.unmodifiable(data),
      date = statsParse(data['date'] as String);
  final Map<String, dynamic> data;
  final DateTime date;
  bool get finalized => data['finalized'] == true;
  Map<String, dynamic>? get sleepDetails =>
      (data['sleepDetails'] as Map?)?.cast<String, dynamic>();
  double? value(BodyMetric metric) {
    if (metric.manual || metric.perception) return null;
    final availability = data['availability'] as Map?;
    if (availability?[metric.key] == false) return null;
    final raw = data[metric.key];
    if (raw is! num || !raw.isFinite || raw < 0) return null;
    // Legacy snapshots used zero as fallback when an activity API failed.
    // Without explicit provenance, zero is ambiguous and is not an observation.
    if (availability == null &&
        raw == 0 &&
        {
          BodyMetric.steps,
          BodyMetric.distance,
          BodyMetric.active,
        }.contains(metric)) {
      return null;
    }
    if ({
          BodyMetric.sleep,
          BodyMetric.restingHr,
          BodyMetric.hrv,
        }.contains(metric) &&
        raw == 0) {
      return null;
    }
    if (metric == BodyMetric.efficiency && raw > 100) return null;
    return raw.toDouble();
  }
}

class BodySummary {
  BodySummary(Iterable<double?> observations, this.expected) {
    values = observations.whereType<double>().where((v) => v.isFinite).toList();
  }
  final int expected;
  late final List<double> values;
  int get count => values.length;
  double get coverage => expected == 0 ? 0 : count / expected;
  double? get total => count == 0 ? null : values.reduce((a, b) => a + b);
  double? get mean => total == null ? null : total! / count;
  double? get sd => count < 2
      ? null
      : math.sqrt(
          values.fold<double>(0, (sum, v) => sum + math.pow(v - mean!, 2)) /
              (count - 1),
        );
  String get coverageLabel =>
      '$count / $expected giorni · ${(coverage * 100).round()}% copertura';
}

List<double?> movingAverage(List<double?> points, {int window = 7}) => [
  for (var i = 0; i < points.length; i++)
    // No interpolation across a missing day; partial windows are explicit.
    points[i] == null
        ? null
        : BodySummary(
            points.sublist(math.max(0, i - window + 1), i + 1),
            window,
          ).mean,
];

class WeeklyBodyBucket {
  WeeklyBodyBucket(
    this.start,
    this.range,
    this.summary, {
    this.hasProvisional = false,
  });
  final DateTime start;
  final BodyRange range;
  final BodySummary summary;
  final bool hasProvisional;
  bool get partial => range.days < 7 || summary.count < 7 || hasProvisional;
}

List<WeeklyBodyBucket> weeklyBuckets(
  List<BodyDay> days,
  BodyRange range,
  BodyMetric metric,
) {
  final byDate = {for (final d in days) statsKey(d.date): d};
  final groups = <DateTime, List<DateTime>>{};
  for (final d in range.dates) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    groups.putIfAbsent(monday, () => []).add(d);
  }
  return [
    for (final entry in groups.entries)
      WeeklyBodyBucket(
        entry.key,
        BodyRange(entry.value.first, entry.value.last),
        BodySummary(
          entry.value.map((d) => byDate[statsKey(d)]?.value(metric)),
          entry.value.length,
        ),
        hasProvisional: entry.value.any(
          (d) => byDate[statsKey(d)]?.finalized == false,
        ),
      ),
  ];
}

enum ExperimentStatus {
  draft('Bozza'),
  running('In corso'),
  completed('Concluso'),
  archived('Archiviato');

  const ExperimentStatus(this.label);
  final String label;
}

class BodyExperiment {
  BodyExperiment({
    this.id,
    required this.name,
    this.description = '',
    this.objective = '',
    this.activity = '',
    this.plannedMinutes = 5,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.plannedTime,
    required this.range,
    required this.baseline,
    this.primary = BodyMetric.hrv,
    this.secondary = const [
      BodyMetric.sleep,
      BodyMetric.restingHr,
      BodyMetric.calm,
    ],
    this.notes = '',
    this.status = ExperimentStatus.draft,
    this.repeatedFrom,
  });
  final String? id, repeatedFrom, plannedTime;
  final String name, description, objective, activity, notes;
  final int plannedMinutes;
  final List<int> weekdays;
  final BodyRange range, baseline;
  final BodyMetric primary;
  final List<BodyMetric> secondary;
  final ExperimentStatus status;
  List<BodyMetric> get metrics =>
      {primary, ...secondary, BodyMetric.calm}.toList();
  int get plannedSessions =>
      range.dates.where((d) => weekdays.contains(d.weekday)).length;
  factory BodyExperiment.fromJson(Map<String, dynamic> j) {
    final protocol = j['protocol'] as Map? ?? {};
    return BodyExperiment(
      id: j['id'] as String,
      name: j['name'] as String,
      description: j['description'] as String? ?? '',
      objective: j['objective'] as String? ?? '',
      activity: protocol['activity'] as String? ?? '',
      plannedMinutes: (protocol['minutes'] as num?)?.toInt() ?? 5,
      weekdays:
          (protocol['weekdays'] as List?)?.cast<int>() ?? [1, 2, 3, 4, 5, 6, 7],
      plannedTime: protocol['time'] as String?,
      range: BodyRange(statsParse(j['start_date']), statsParse(j['end_date'])),
      baseline: BodyRange(
        statsParse(j['baseline_start']),
        statsParse(j['baseline_end']),
      ),
      primary: BodyMetric.parse(j['primary_metric']),
      secondary: (j['secondary_metrics'] as List)
          .map((m) => BodyMetric.parse(m as String))
          .toList(),
      notes: j['initial_notes'] as String? ?? '',
      status: ExperimentStatus.values.byName(j['status']),
      repeatedFrom: j['repeated_from'] as String?,
    );
  }
  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'description': description,
    'objective': objective,
    'protocol': {
      'activity': activity,
      'minutes': plannedMinutes,
      'weekdays': weekdays,
      'time': plannedTime,
    },
    'start_date': statsKey(range.start),
    'end_date': statsKey(range.end),
    'baseline_start': statsKey(baseline.start),
    'baseline_end': statsKey(baseline.end),
    'primary_metric': primary.key,
    'secondary_metrics': secondary.map((m) => m.key).toList(),
    'initial_notes': notes,
    'status': status.name,
    'repeated_from': repeatedFrom,
  };
  void validate() {
    if (name.trim().isEmpty || name.length > 160) {
      throw ArgumentError('Inserisci un nome valido (massimo 160 caratteri).');
    }
    if (!baseline.end.isBefore(range.start)) {
      throw ArgumentError('Il riferimento deve precedere l’esperimento.');
    }
    if (range.days > 3653 || baseline.days > 3653) {
      throw ArgumentError('Il periodo massimo è di 10 anni.');
    }
    if (weekdays.isEmpty ||
        weekdays.any((d) => d < 1 || d > 7) ||
        plannedMinutes < 1 ||
        plannedMinutes > 1440) {
      throw ArgumentError('Controlla durata e frequenza del protocollo.');
    }
  }
}

class ExperimentLog {
  ExperimentLog({
    required this.experimentId,
    required DateTime date,
    this.sessionStatus,
    this.minutes,
    this.time,
    this.calm,
    this.stress,
    this.notes = '',
    this.context = const {},
  }) : date = statsDate(date);
  final String experimentId;
  final DateTime date;
  final String? sessionStatus, time;
  final int? minutes;
  final double? calm, stress;
  final String notes;
  final Map<String, bool?> context;
  factory ExperimentLog.fromJson(Map<String, dynamic> j) => ExperimentLog(
    experimentId: j['experiment_id'],
    date: statsParse(j['day']),
    sessionStatus: j['session_status'],
    minutes: j['duration_minutes'],
    time: j['practice_time'],
    calm: (j['calm'] as num?)?.toDouble(),
    stress: (j['stress'] as num?)?.toDouble(),
    notes: j['notes'] ?? '',
    context: (j['context'] as Map).cast<String, bool?>(),
  );
  Map<String, Object?> toJson() => {
    'experiment_id': experimentId,
    'day': statsKey(date),
    'session_status': sessionStatus,
    'duration_minutes': minutes,
    'practice_time': time,
    'calm': calm,
    'stress': stress,
    'notes': notes,
    'context': context,
    'source': 'manual',
  };
  double? value(BodyMetric metric) => metric == BodyMetric.calm
      ? calm
      : metric == BodyMetric.stress
      ? stress
      : null;
}

class ExperimentComparison {
  ExperimentComparison({
    required this.experiment,
    required List<BodyDay> days,
    required this.logs,
    required DateTime today,
    List<PerceptionEntry> perceptions = const [],
    this.excludedFactors = const {},
  }) : today = statsDate(today),
       calmByDate = PerceptionAnalysis(perceptions, emotion: 'calm').dailyMeans,
       days = {for (final d in days) statsKey(d.date): d};
  final BodyExperiment experiment;
  final Map<String, BodyDay> days;
  final Map<String, double> calmByDate;
  final List<ExperimentLog> logs;
  final DateTime today;
  final Set<String> excludedFactors;
  late final Map<String, ExperimentLog> _logsByDate = {
    for (final log in logs) statsKey(log.date): log,
  };
  ExperimentLog? logAt(DateTime day) {
    return _logsByDate[statsKey(day)];
  }

  bool excluded(DateTime day) =>
      excludedFactors.any((f) => logAt(day)?.context[f] == true);
  double? value(DateTime day, BodyMetric metric) {
    if (statsDate(day).isAfter(today) || excluded(day)) return null;
    if (metric == BodyMetric.calm) return calmByDate[statsKey(day)];
    return metric.manual
        ? logAt(day)?.value(metric)
        : days[statsKey(day)]?.value(metric);
  }

  BodySummary summary(BodyRange range, BodyMetric metric) => BodySummary(
    range.dates.map((d) => value(d, metric)),
    range.dates.where((d) => !d.isAfter(today)).length,
  );
  int excludedCount(BodyRange range) =>
      range.dates.where((d) => !d.isAfter(today) && excluded(d)).length;
  int get availableDays =>
      experiment.range.dates.where((d) => !d.isAfter(today)).length;
  int get completed => logs
      .where(
        (l) =>
            experiment.range.contains(l.date) &&
            !l.date.isAfter(today) &&
            experiment.weekdays.contains(l.date.weekday) &&
            l.sessionStatus == 'completed',
      )
      .length;
  bool get provisional =>
      experiment.status == ExperimentStatus.running ||
      experiment.range.end.isAfter(today);
  String observation(BodyMetric metric) {
    final before = summary(experiment.baseline, metric),
        during = summary(experiment.range, metric);
    if (before.count < 2 || during.count < 2) {
      return 'Dati insufficienti per il confronto: servono almeno 2 osservazioni valide in ciascun periodo (${before.count} prima, ${during.count} durante).';
    }
    return 'Durante il periodo osservato, ${metric.label.toLowerCase()} media: ${metric.format(during.mean)}; differenza ${metric.format(during.mean! - before.mean!, delta: true)} rispetto al riferimento. Confronto descrittivo: non dimostra un rapporto causa-effetto.';
  }
}
