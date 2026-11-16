enum RoutineStatus { unmarked, ok, ko }

class RoutineDetailOption {
  const RoutineDetailOption({
    required this.id,
    required this.label,
    required this.position,
    this.score,
  });

  factory RoutineDetailOption.fromJson(Map<String, dynamic> json) {
    return RoutineDetailOption(
      id: json['id'] as String,
      label: json['label'] as String,
      position: (json['position'] as num?)?.toInt() ?? 0,
      score:
          (json['score'] as num?)?.toDouble() ??
          (json['koScoreFraction'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String label;
  final int position;
  final double? score;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'position': position,
    'score': score,
  };
}

class RoutineDefinition {
  const RoutineDefinition({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.position,
    this.weight = 1,
    this.detailOptions = const <RoutineDetailOption>[],
    this.validFrom,
    this.validUntil,
  });

  factory RoutineDefinition.fromJson(Map<String, dynamic> json) {
    return RoutineDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      iconKey: json['iconKey'] as String? ?? 'task',
      position: (json['position'] as num?)?.toInt() ?? 0,
      weight: (json['weight'] as num?)?.toDouble() ?? 1,
      detailOptions: (json['detailOptions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RoutineDetailOption.fromJson)
          .toList(growable: false),
      validFrom: dateFromJson(json['validFrom']),
      validUntil: dateFromJson(json['validUntil']),
    );
  }

  final String id;
  final String name;
  final String iconKey;
  final int position;
  final double weight;
  final List<RoutineDetailOption> detailOptions;
  final DateTime? validFrom;
  final DateTime? validUntil;

  bool isValidOn(DateTime date) {
    final day = dateOnly(date);
    return (validFrom == null || !day.isBefore(validFrom!)) &&
        (validUntil == null || day.isBefore(validUntil!));
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'iconKey': iconKey,
    'position': position,
    'weight': weight,
    'detailOptions': [for (final option in detailOptions) option.toJson()],
    'validFrom': dateToJson(validFrom),
    'validUntil': dateToJson(validUntil),
  };
}

class RoutineEntry {
  const RoutineEntry({
    this.status = RoutineStatus.unmarked,
    this.completionTimeMinutes,
    this.selectedDetailOptionId,
    this.selectedDetailLabelSnapshot,
    this.selectedDetailScoreSnapshot,
    this.notes = '',
  });

  factory RoutineEntry.fromJson(Map<String, dynamic> json) {
    final status =
        RoutineStatus.values
            .where((candidate) => candidate.name == json['status'])
            .firstOrNull ??
        ((json['isCompleted'] as bool? ?? false)
            ? RoutineStatus.ok
            : RoutineStatus.ko);
    return RoutineEntry(
      status: status,
      completionTimeMinutes: status == RoutineStatus.ok
          ? _validMinutes(json['completionTimeMinutes'])
          : null,
      selectedDetailOptionId: json['selectedDetailOptionId'] as String?,
      selectedDetailLabelSnapshot:
          json['selectedDetailLabelSnapshot'] as String? ??
          json['selectedGymPlan'] as String?,
      selectedDetailScoreSnapshot: (json['selectedDetailScoreSnapshot'] as num?)
          ?.toDouble(),
      notes: json['notes'] as String? ?? '',
    );
  }

  final RoutineStatus status;
  final int? completionTimeMinutes;
  final String? selectedDetailOptionId;
  final String? selectedDetailLabelSnapshot;
  final double? selectedDetailScoreSnapshot;
  final String notes;

  bool get isCompleted => status == RoutineStatus.ok;
  bool get isMarked => status != RoutineStatus.unmarked;

  RoutineEntry copyWith({
    RoutineStatus? status,
    Object? completionTimeMinutes = _unset,
    Object? selectedDetailOptionId = _unset,
    Object? selectedDetailLabelSnapshot = _unset,
    Object? selectedDetailScoreSnapshot = _unset,
    String? notes,
  }) {
    return RoutineEntry(
      status: status ?? this.status,
      completionTimeMinutes: identical(completionTimeMinutes, _unset)
          ? this.completionTimeMinutes
          : completionTimeMinutes as int?,
      selectedDetailOptionId: identical(selectedDetailOptionId, _unset)
          ? this.selectedDetailOptionId
          : selectedDetailOptionId as String?,
      selectedDetailLabelSnapshot:
          identical(selectedDetailLabelSnapshot, _unset)
          ? this.selectedDetailLabelSnapshot
          : selectedDetailLabelSnapshot as String?,
      selectedDetailScoreSnapshot:
          identical(selectedDetailScoreSnapshot, _unset)
          ? this.selectedDetailScoreSnapshot
          : selectedDetailScoreSnapshot as double?,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status.name,
    'isCompleted': isCompleted,
    'completionTimeMinutes': completionTimeMinutes,
    'selectedDetailOptionId': selectedDetailOptionId,
    'selectedDetailLabelSnapshot': selectedDetailLabelSnapshot,
    'selectedDetailScoreSnapshot': selectedDetailScoreSnapshot,
    'notes': notes,
  };
}

const _unset = Object();

int? _validMinutes(Object? value) {
  final minutes = (value as num?)?.toInt();
  return minutes != null && minutes >= 0 && minutes < 24 * 60 ? minutes : null;
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Sposta di [days] giorni di calendario. Non usare `add(Duration(days:))`:
/// nei giorni del cambio dell'ora un giorno dura 23 o 25 ore e la data
/// risultante finisce alle 23:00 o all'01:00, cioè non coincide più con le
/// date salvate.
DateTime shiftDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);

DateTime? dateFromJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return dateOnly(DateTime.parse(value));
}

String? dateToJson(DateTime? value) => value == null ? null : formatDate(value);

String formatDate(DateTime value) {
  final date = dateOnly(value);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

const defaultNutritionOptions = <RoutineDetailOption>[
  RoutineDetailOption(
    id: 'alimentazione_sgarro_lieve',
    label: 'Livello 1 - lieve',
    position: 0,
    score: 0.75,
  ),
  RoutineDetailOption(
    id: 'alimentazione_sgarro_moderato',
    label: 'Livello 2 - moderato',
    position: 1,
    score: 0.50,
  ),
  RoutineDetailOption(
    id: 'alimentazione_sgarro_importante',
    label: 'Livello 3 - importante',
    position: 2,
    score: 0.25,
  ),
  RoutineDetailOption(
    id: 'alimentazione_sgarro_grave',
    label: 'Livello 4 - grave',
    position: 3,
    score: 0,
  ),
];

const defaultGymOptions = <RoutineDetailOption>[
  RoutineDetailOption(id: 'palestra_forza', label: 'Forza', position: 0),
  RoutineDetailOption(id: 'palestra_cardio', label: 'Cardio', position: 1),
  RoutineDetailOption(
    id: 'palestra_mobilita',
    label: 'Mobilità e stretching',
    position: 2,
  ),
];

/// Abitudini proposte al primo avvio. Ognuno può rinominarle, toglierle o
/// aggiungerne di nuove dall'app: sono solo un punto di partenza.
const _currentDefaults = <RoutineDefinition>[
  RoutineDefinition(
    id: 'meditazione',
    name: 'Meditazione',
    iconKey: 'meditation',
    position: 0,
  ),
  RoutineDefinition(
    id: 'palestra',
    name: 'Allenamento',
    iconKey: 'gym',
    position: 1,
    detailOptions: defaultGymOptions,
  ),
  RoutineDefinition(
    id: 'alimentazione',
    name: 'Alimentazione',
    iconKey: 'food',
    position: 2,
    detailOptions: defaultNutritionOptions,
  ),
  RoutineDefinition(
    id: 'studio',
    name: 'Studio',
    iconKey: 'study',
    position: 3,
  ),
  RoutineDefinition(id: 'libro', name: 'Lettura', iconKey: 'book', position: 4),
  RoutineDefinition(
    id: 'diario',
    name: 'Diario',
    iconKey: 'journal',
    position: 5,
  ),
  RoutineDefinition(
    id: 'camminata',
    name: 'Camminata',
    iconKey: 'walking',
    position: 6,
  ),
];

List<RoutineDefinition> buildDefaultRoutineHistory() {
  // Tutte le abitudini predefinite valgono dal primo giorno di utilizzo.
  return List<RoutineDefinition>.of(_currentDefaults);
}
