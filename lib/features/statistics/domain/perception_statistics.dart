enum PerceivedEmotion {
  hyperfocus('hyperfocus', '🧠', 'Iperfocus'),
  satisfied('satisfied', '😌', 'Soddisfatto'),
  content('content', '😊', 'Contento'),
  happy('happy', '😀', 'Felice'),
  neutral('neutral', '😐', 'Neutro'),
  joy('joy', '😁', 'Gioia'),
  sad('sad', '😢', 'Triste'),
  angry('angry', '😡', 'Arrabbiato'),
  irritated('irritated', '😤', 'Irritato'),
  anxious('anxious', '😰', 'Ansioso'),
  afraid('afraid', '😨', 'Paura'),
  excited('excited', '🤩', 'Eccitato'),
  tired('tired', '😴', 'Stanco'),
  stressed('stressed', '🤯', 'Stressato'),
  calm('calm', '🧘', 'Calmo'),
  inspired('inspired', '💡', 'Ispirato'),
  overwhelmed('overwhelmed', '😵', 'Sopraffatto'),
  grateful('grateful', '🙏', 'Grato'),
  restless('restless', '🌪️', 'Irrequieto'),
  bored('bored', '😑', 'Annoiato'),
  confused('confused', '🌀', 'Confuso');

  const PerceivedEmotion(this.key, this.emoji, this.label);
  final String key, emoji, label;

  static PerceivedEmotion? parse(String key) =>
      values.where((emotion) => emotion.key == key).firstOrNull;
}

class PerceptionEntry {
  PerceptionEntry({
    required this.id,
    required DateTime date,
    required this.emotion,
    required this.intensity,
    required this.energy,
    required this.recordedAt,
  }) : date = DateTime.utc(date.year, date.month, date.day);

  factory PerceptionEntry.fromJson(Map<String, dynamic> row) => PerceptionEntry(
    id: row['id'] as String,
    date: DateTime.parse(row['reference_date'] as String),
    emotion: row['emotion'] as String,
    intensity: (row['intensity'] as num).toDouble(),
    energy: row['energy'] as String,
    recordedAt: DateTime.parse(row['recorded_at'] as String),
  );

  final String id, emotion, energy;
  final DateTime date, recordedAt;
  final double intensity;
  String get dateKey => date.toIso8601String().substring(0, 10);
  String get label => PerceivedEmotion.parse(emotion)?.label ?? emotion;
  String get emoji => PerceivedEmotion.parse(emotion)?.emoji ?? '💭';
  bool get hasRating =>
      emotion != 'no_data' &&
      intensity.isFinite &&
      intensity >= 1 &&
      intensity <= 5;
  String get energyLabel => switch (energy) {
    'depleted' => 'A terra',
    'low' => 'Bassa',
    'medium' => 'Media',
    'high' => 'Alta',
    _ => 'Non registrata',
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'reference_date': dateKey,
    'emotion': emotion,
    'intensity': intensity,
    'energy': energy,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
  };
}

/// Each recorded day contributes once, regardless of the number of check-ins.
class PerceptionAnalysis {
  PerceptionAnalysis(Iterable<PerceptionEntry> entries, {String? emotion})
    : entries = entries
          .where(
            (e) => e.hasRating && (emotion == null || e.emotion == emotion),
          )
          .toList(growable: false);

  final List<PerceptionEntry> entries;
  late final Map<String, List<PerceptionEntry>> byDate = _groupByDate();
  Map<String, List<PerceptionEntry>> _groupByDate() {
    final result = <String, List<PerceptionEntry>>{};
    for (final entry in entries) {
      result.putIfAbsent(entry.dateKey, () => []).add(entry);
    }
    return result;
  }

  late final Map<String, double> dailyMeans = {
    for (final group in byDate.entries)
      group.key:
          group.value.fold<double>(0, (sum, e) => sum + e.intensity) /
          group.value.length,
  };
  late final Map<String, int> frequencies = _frequencies();
  Map<String, int> _frequencies() {
    final result = <String, int>{};
    for (final entry in entries) {
      result.update(entry.emotion, (count) => count + 1, ifAbsent: () => 1);
    }
    return result;
  }
}
