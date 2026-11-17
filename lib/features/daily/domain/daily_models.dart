/// Modelli della scheda Quotidianità e della scheda Sport.
///
/// Sono gli stessi dati dell'app per iPhone (stesse tabelle Supabase): le
/// chiavi salvate non vanno cambiate.
library;

import '../../../core/i18n/i18n.dart';

enum EmotionTone { good, neutral, hard }

enum DailyEmotion {
  happy('happy', '😀', 'Felice', 'Happy', EmotionTone.good),
  joy('joy', '😁', 'Gioia', 'Joyful', EmotionTone.good),
  content('content', '😊', 'Contento', 'Content', EmotionTone.good),
  satisfied('satisfied', '😌', 'Soddisfatto', 'Satisfied', EmotionTone.good),
  calm('calm', '🧘', 'Calmo', 'Calm', EmotionTone.good),
  grateful('grateful', '🙏', 'Grato', 'Grateful', EmotionTone.good),
  inspired('inspired', '💡', 'Ispirato', 'Inspired', EmotionTone.good),
  excited('excited', '🤩', 'Eccitato', 'Excited', EmotionTone.good),
  hyperfocus('hyperfocus', '🧠', 'Iperfocus', 'Hyperfocus', EmotionTone.good),
  neutral('neutral', '😐', 'Neutro', 'Neutral', EmotionTone.neutral),
  tired('tired', '😴', 'Stanco', 'Tired', EmotionTone.neutral),
  bored('bored', '😑', 'Annoiato', 'Bored', EmotionTone.neutral),
  confused('confused', '🌀', 'Confuso', 'Confused', EmotionTone.neutral),
  restless('restless', '🌪️', 'Irrequieto', 'Restless', EmotionTone.hard),
  anxious('anxious', '😰', 'Ansioso', 'Anxious', EmotionTone.hard),
  stressed('stressed', '🤯', 'Stressato', 'Stressed', EmotionTone.hard),
  overwhelmed(
    'overwhelmed',
    '😵',
    'Sopraffatto',
    'Overwhelmed',
    EmotionTone.hard,
  ),
  irritated('irritated', '😤', 'Irritato', 'Irritated', EmotionTone.hard),
  angry('angry', '😡', 'Arrabbiato', 'Angry', EmotionTone.hard),
  sad('sad', '😢', 'Triste', 'Sad', EmotionTone.hard),
  afraid('afraid', '😨', 'Paura', 'Afraid', EmotionTone.hard),
  noData('no_data', '🚫', 'No dati', 'No data', EmotionTone.neutral);

  const DailyEmotion(
    this.key,
    this.emoji,
    this.italian,
    this.english,
    this.tone,
  );
  final String key, emoji, italian, english;
  String get label => tr(italian, english);
  final EmotionTone tone;

  static DailyEmotion? fromKey(Object? value) =>
      values.where((e) => e.key == value).firstOrNull;
}

enum DailyEnergy {
  depleted('depleted', 'A terra', 'Drained', '🪫'),
  low('low', 'Bassa', 'Low', '🔅'),
  medium('medium', 'Media', 'Medium', '🔆'),
  high('high', 'Alta', 'High', '⚡'),
  noData('no_data', 'No dati', 'No data', '');

  const DailyEnergy(this.key, this.italian, this.english, this.emoji);
  final String key, italian, english, emoji;
  String get label => tr(italian, english);

  static DailyEnergy? fromKey(Object? value) =>
      values.where((e) => e.key == value).firstOrNull;
}

Map<int, String> get concentrationLabels => <int, String>{
  1: tr('Molto bassa', 'Very low'),
  2: tr('Bassa', 'Low'),
  3: tr('Media', 'Medium'),
  4: tr('Alta', 'High'),
  5: tr('Massima', 'Maximum'),
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
  day('daily_concentration_entries', 'Durante la giornata', 'During the day'),
  meditation(
    'meditation_concentration_entries',
    'In meditazione',
    'In meditation',
  );

  const ConcentrationKind(this.table, this.italian, this.english);
  final String table, italian, english;
  String get label => tr(italian, english);
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
  diamond('Diamante', 'Diamond', '💎', 2),
  platinum('Platino', 'Platinum', '🏆', 1.6),
  gold('Oro', 'Gold', '🥇', 1.2),
  silver('Argento', 'Silver', '🥈', .8),
  bronze('Bronzo', 'Bronze', '🥉', .4),
  tooMuch('Troppo', 'Too much', '📵', 0);

  const ScreenTimeMedal(this.italian, this.english, this.emoji, this.bonus);
  final String italian, english, emoji;
  String get label => tr(italian, english);
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
  none('Ancora nessuna coppa', 'No cup yet', '🎯', 0),
  bronze('Bronzo', 'Bronze', '🥉', 20),
  silver('Argento', 'Silver', '🥈', 50),
  gold('Oro', 'Gold', '🥇', 70),
  platinum('Platino', 'Platinum', '🏆', 80),
  diamond('Diamante', 'Diamond', '💎', 90);

  const DayMedal(this.italian, this.english, this.emoji, this.threshold);
  final String italian, english, emoji;
  String get label => tr(italian, english);
  final int threshold;

  static DayMedal fromRate(double rate) {
    final percent = rate * 100 + 1e-9;
    return values.lastWhere((m) => percent >= m.threshold);
  }

  DayMedal? get next => index + 1 < values.length ? values[index + 1] : null;
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
      kind == ConcentrationKind.day
      ? dayConcentration
      : meditationConcentration;
}

enum BodyMetric {
  weight('weight_kg', 'Peso', 'Weight', 'kg'),
  arms('arms_cm', 'Braccia', 'Arms', 'cm'),
  triceps('triceps_cm', 'Tricipiti', 'Triceps', 'cm'),
  chest('chest_cm', 'Petto', 'Chest', 'cm'),
  waist('waist_cm', 'Vita', 'Waist', 'cm'),
  thigh('thigh_cm', 'Coscia', 'Thigh', 'cm');

  const BodyMetric(this.column, this.italian, this.english, this.unit);
  final String column, italian, english, unit;
  String get label => tr(italian, english);
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
