/// Modelli della scheda Quotidianità e della scheda Sport.
///
/// Sono gli stessi dati dell'app per iPhone (stesse tabelle Supabase): le
/// chiavi salvate non vanno cambiate.
library;

enum EmotionTone { good, neutral, hard }

enum DailyEmotion {
  happy('happy', '😀', 'Felice', EmotionTone.good),
  joy('joy', '😁', 'Gioia', EmotionTone.good),
  content('content', '😊', 'Contento', EmotionTone.good),
  satisfied('satisfied', '😌', 'Soddisfatto', EmotionTone.good),
  calm('calm', '🧘', 'Calmo', EmotionTone.good),
  grateful('grateful', '🙏', 'Grato', EmotionTone.good),
  inspired('inspired', '💡', 'Ispirato', EmotionTone.good),
  excited('excited', '🤩', 'Eccitato', EmotionTone.good),
  hyperfocus('hyperfocus', '🧠', 'Iperfocus', EmotionTone.good),
  neutral('neutral', '😐', 'Neutro', EmotionTone.neutral),
  tired('tired', '😴', 'Stanco', EmotionTone.neutral),
  bored('bored', '😑', 'Annoiato', EmotionTone.neutral),
  confused('confused', '🌀', 'Confuso', EmotionTone.neutral),
  restless('restless', '🌪️', 'Irrequieto', EmotionTone.hard),
  anxious('anxious', '😰', 'Ansioso', EmotionTone.hard),
  stressed('stressed', '🤯', 'Stressato', EmotionTone.hard),
  overwhelmed('overwhelmed', '😵', 'Sopraffatto', EmotionTone.hard),
  irritated('irritated', '😤', 'Irritato', EmotionTone.hard),
  angry('angry', '😡', 'Arrabbiato', EmotionTone.hard),
  sad('sad', '😢', 'Triste', EmotionTone.hard),
  afraid('afraid', '😨', 'Paura', EmotionTone.hard),
  noData('no_data', '🚫', 'No dati', EmotionTone.neutral);

  const DailyEmotion(this.key, this.emoji, this.label, this.tone);
  final String key, emoji, label;
  final EmotionTone tone;

  static DailyEmotion? fromKey(Object? value) =>
      values.where((e) => e.key == value).firstOrNull;
}

enum DailyEnergy {
  depleted('depleted', 'A terra', '🪫'),
  low('low', 'Bassa', '🔅'),
  medium('medium', 'Media', '🔆'),
  high('high', 'Alta', '⚡'),
  noData('no_data', 'No dati', '');

  const DailyEnergy(this.key, this.label, this.emoji);
  final String key, label, emoji;

  static DailyEnergy? fromKey(Object? value) =>
      values.where((e) => e.key == value).firstOrNull;
}

const concentrationLabels = <int, String>{
  1: 'Molto bassa',
  2: 'Bassa',
  3: 'Media',
  4: 'Alta',
  5: 'Massima',
};

class EmotionEntry {
  const EmotionEntry({
    required this.id,
    required this.emotion,
    required this.intensity,
    required this.energy,
    required this.recordedAt,
    this.concentration,
  });

  static EmotionEntry? fromRow(Map<String, dynamic> row) {
    final emotion = DailyEmotion.fromKey(row['emotion']);
    final energy = DailyEnergy.fromKey(row['energy']);
    final at = DateTime.tryParse('${row['recorded_at'] ?? ''}');
    final id = row['id'];
    if (id is! String || emotion == null || energy == null || at == null) {
      return null;
    }
    return EmotionEntry(
      id: id,
      emotion: emotion,
      intensity: ((row['intensity'] as num?)?.toInt() ?? 3).clamp(1, 5),
      energy: energy,
      concentration: (row['concentration'] as num?)?.toInt(),
      recordedAt: at.toLocal(),
    );
  }

  final String id;
  final DailyEmotion emotion;
  final int intensity;
  final DailyEnergy energy;
  final int? concentration;
  final DateTime recordedAt;
}

enum ConcentrationKind {
  day('daily_concentration_entries', 'Durante la giornata'),
  meditation('meditation_concentration_entries', 'In meditazione');

  const ConcentrationKind(this.table, this.label);
  final String table, label;
}

class ConcentrationEntry {
  const ConcentrationEntry({
    required this.id,
    required this.level,
    required this.recordedAt,
    this.fromEmotion = false,
  });

  static ConcentrationEntry? fromRow(Map<String, dynamic> row) {
    final level = (row['concentration'] as num?)?.toInt();
    final at = DateTime.tryParse('${row['recorded_at'] ?? ''}');
    final id = row['id'];
    if (id is! String || level == null || at == null) return null;
    return ConcentrationEntry(
      id: id,
      level: level.clamp(1, 5),
      recordedAt: at.toLocal(),
      // Creata dal database insieme a un check-in emotivo: si toglie da lì.
      fromEmotion: '${row['source_key'] ?? ''}'.startsWith('emotion:'),
    );
  }

  final String id;
  final int level;
  final DateTime recordedAt;
  final bool fromEmotion;
}

class ScreenTimeExclusion {
  const ScreenTimeExclusion({
    required this.id,
    required this.name,
    required this.minutes,
  });

  static ScreenTimeExclusion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'];
    final minutes = (raw['minutes'] as num?)?.toInt();
    if (id is! String ||
        name is! String ||
        name.trim().isEmpty ||
        minutes == null ||
        minutes <= 0 ||
        minutes > 24 * 60) {
      return null;
    }
    return ScreenTimeExclusion(id: id, name: name.trim(), minutes: minutes);
  }

  final String id, name;
  final int minutes;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'minutes': minutes};
}

enum ScreenTimeMedal {
  diamond('Diamante', '💎', 2),
  platinum('Platino', '🏆', 1.6),
  gold('Oro', '🥇', 1.2),
  silver('Argento', '🥈', .8),
  bronze('Bronzo', '🥉', .4),
  tooMuch('Troppo', '📵', 0);

  const ScreenTimeMedal(this.label, this.emoji, this.bonus);
  final String label, emoji;
  final double bonus;

  static ScreenTimeMedal fromMinutes(int minutes) => minutes < 90
      ? diamond
      : minutes < 120
      ? platinum
      : minutes < 165
      ? gold
      : minutes < 180
      ? silver
      : minutes < 225
      ? bronze
      : tooMuch;
}

class ScreenTime {
  const ScreenTime({required this.totalMinutes, this.exclusions = const []});
  final int totalMinutes;
  final List<ScreenTimeExclusion> exclusions;

  int get excludedMinutes => exclusions.fold(0, (sum, e) => sum + e.minutes);

  /// Tempo che conta davvero: totale meno le attività escluse.
  int get countedMinutes =>
      (totalMinutes - excludedMinutes).clamp(0, 24 * 60).toInt();
  ScreenTimeMedal get medal => ScreenTimeMedal.fromMinutes(countedMinutes);
}

String formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Accetta "2:15", "02:15", "2.15", "215" (2 ore e 15) e "45" (minuti).
int? parseMinutes(String raw) {
  final value = raw.trim().replaceAll('.', ':').replaceAll(',', ':');
  if (value.isEmpty) return null;
  final match = RegExp(r'^(\d{1,2}):([0-5]?\d)$').firstMatch(value);
  int? total;
  if (match != null) {
    total = int.parse(match[1]!) * 60 + int.parse(match[2]!);
  } else if (RegExp(r'^\d{1,4}$').hasMatch(value)) {
    final n = int.parse(value);
    total = value.length <= 2 ? n : (n ~/ 100) * 60 + n % 100;
    if (value.length > 2 && n % 100 > 59) return null;
  }
  return total != null && total <= 24 * 60 ? total : null;
}

/// Coppa della giornata, con le stesse soglie dell'app per iPhone.
enum DayMedal {
  none('Ancora nessuna coppa', '🎯', 0),
  bronze('Bronzo', '🥉', 20),
  silver('Argento', '🥈', 50),
  gold('Oro', '🥇', 70),
  platinum('Platino', '🏆', 80),
  diamond('Diamante', '💎', 90);

  const DayMedal(this.label, this.emoji, this.threshold);
  final String label, emoji;
  final int threshold;

  static DayMedal fromRate(double rate) {
    final percent = rate * 100 + 1e-9;
    return values.lastWhere((m) => percent >= m.threshold);
  }

  DayMedal? get next =>
      index + 1 < values.length ? values[index + 1] : null;
}

class DailyLifeDay {
  const DailyLifeDay({
    this.emotions = const [],
    this.dayConcentration = const [],
    this.meditationConcentration = const [],
    this.movement,
    this.screenTime,
  });
  final List<EmotionEntry> emotions;
  final List<ConcentrationEntry> dayConcentration, meditationConcentration;

  /// Movimento percepito, 1–5 (0 nei vecchi dati = non registrato).
  final int? movement;

  /// Uso del cellulare del giorno precedente.
  final ScreenTime? screenTime;

  List<ConcentrationEntry> concentration(ConcentrationKind kind) =>
      kind == ConcentrationKind.day ? dayConcentration : meditationConcentration;
}

enum BodyMetric {
  weight('weight_kg', 'Peso', 'kg'),
  arms('arms_cm', 'Braccia', 'cm'),
  triceps('triceps_cm', 'Tricipiti', 'cm'),
  chest('chest_cm', 'Petto', 'cm'),
  waist('waist_cm', 'Vita', 'cm'),
  thigh('thigh_cm', 'Coscia', 'cm');

  const BodyMetric(this.column, this.label, this.unit);
  final String column, label, unit;
}

class BodyMeasurement {
  const BodyMeasurement({required this.date, required this.values});

  static BodyMeasurement? fromRow(Map<String, dynamic> row) {
    final date = DateTime.tryParse('${row['reference_date'] ?? ''}');
    if (date == null) return null;
    return BodyMeasurement(
      date: DateTime(date.year, date.month, date.day),
      values: {
        for (final metric in BodyMetric.values)
          if ((row[metric.column] as num?)?.toDouble() case final value?)
            metric: value,
      },
    );
  }

  final DateTime date;
  final Map<BodyMetric, double> values;

  double? operator [](BodyMetric metric) => values[metric];
}
