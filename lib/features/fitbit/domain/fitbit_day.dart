class FitbitDay {
  const FitbitDay({
    this.source = 'fitbit',
    required this.date,
    required this.finalized,
    required this.syncedAt,
    required this.steps,
    required this.distanceKm,
    required this.calories,
    required this.activeMinutes,
    this.sedentaryMinutes,
    this.mindfulnessMinutes,
    this.activeZoneMinutes,
    this.activeZoneMinutesByZone,
    required this.restingHeartRate,
    this.latestHeartRate,
    required this.sleepMinutes,
    required this.sleepEfficiency,
    this.sleepDetails,
    this.oxygenSaturation,
    this.heartRateVariabilityMs,
    this.respiratoryRate,
    this.skinTemperature,
    this.vo2Max,
    this.workouts = const [],
    this.heartProfile = const [],
    this.sleepStages = const [],
    this.stepsTrend = const [],
    this.distanceTrend = const [],
    this.caloriesTrend = const [],
    this.activeMinutesTrend = const [],
    this.sedentaryMinutesTrend = const [],
    this.activeZoneMinutesTrend = const [],
    this.restingHeartRateTrend = const [],
    this.sleepMinutesTrend = const [],
    this.oxygenSaturationTrend = const [],
    this.heartRateVariabilityTrend = const [],
    this.respiratoryRateTrend = const [],
    this.skinTemperatureTrend = const [],
    this.vo2MaxTrend = const [],
  });

  factory FitbitDay.fromJson(Map<String, Object?> json) {
    final trends = json['trends'];
    final trendMap = trends is Map<String, Object?>
        ? trends
        : const <String, Object?>{};
    final oxygen = json['oxygenSaturation'];
    final temperature = json['skinTemperature'];
    final activeZones = json['activeZoneMinutesByZone'];
    final sleepDetails = json['sleepDetails'];
    final vo2Max = json['vo2Max'];
    final latestHeartRate = json['latestHeartRate'];
    return FitbitDay(
      source: 'fitbit',
      date: _requiredString(json, 'date'),
      finalized: json['finalized'] == true,
      syncedAt: DateTime.parse(_requiredString(json, 'syncedAt')),
      steps: _requiredInt(json, 'steps'),
      distanceKm: _requiredNumber(json, 'distanceKm').toDouble(),
      calories: _requiredInt(json, 'calories'),
      activeMinutes: _requiredInt(json, 'activeMinutes'),
      sedentaryMinutes: _nullableInt(json['sedentaryMinutes']),
      mindfulnessMinutes: _nullableInt(json['mindfulnessMinutes']),
      activeZoneMinutes: _nullableInt(json['activeZoneMinutes']),
      activeZoneMinutesByZone: activeZones is Map<String, Object?>
          ? FitbitActiveZoneMinutes.fromJson(activeZones)
          : null,
      restingHeartRate: _nullableInt(json['restingHeartRate']),
      latestHeartRate: latestHeartRate is Map<String, Object?>
          ? FitbitHeartSample.fromJson(latestHeartRate)
          : null,
      sleepMinutes: _nullableInt(json['sleepMinutes']),
      sleepEfficiency: _nullableInt(json['sleepEfficiency']),
      sleepDetails: sleepDetails is Map<String, Object?>
          ? FitbitSleepDetails.fromJson(sleepDetails)
          : null,
      oxygenSaturation: oxygen is Map<String, Object?>
          ? FitbitOxygenSaturation.fromJson(oxygen)
          : null,
      heartRateVariabilityMs: _nullableDouble(json['heartRateVariabilityMs']),
      respiratoryRate: _nullableDouble(json['respiratoryRate']),
      skinTemperature: temperature is Map<String, Object?>
          ? FitbitSkinTemperature.fromJson(temperature)
          : null,
      vo2Max: vo2Max is Map<String, Object?>
          ? FitbitVo2Max.fromJson(vo2Max)
          : null,
      workouts: _objectList(json['workouts'], FitbitWorkout.fromJson),
      heartProfile: _objectList(
        json['heartProfile'],
        FitbitHeartPoint.fromJson,
      ),
      sleepStages: _objectList(json['sleepStages'], FitbitSleepStage.fromJson),
      stepsTrend: _numberList(trendMap['steps']),
      distanceTrend: _numberList(trendMap['distanceKm']),
      caloriesTrend: _numberList(trendMap['calories']),
      activeMinutesTrend: _numberList(trendMap['activeMinutes']),
      sedentaryMinutesTrend: _numberList(trendMap['sedentaryMinutes']),
      activeZoneMinutesTrend: _numberList(trendMap['activeZoneMinutes']),
      restingHeartRateTrend: _numberList(trendMap['restingHeartRate']),
      sleepMinutesTrend: _numberList(trendMap['sleepMinutes']),
      oxygenSaturationTrend: _numberList(trendMap['oxygenSaturation']),
      heartRateVariabilityTrend: _numberList(
        trendMap['heartRateVariabilityMs'],
      ),
      respiratoryRateTrend: _numberList(trendMap['respiratoryRate']),
      skinTemperatureTrend: _numberList(trendMap['skinTemperature']),
      vo2MaxTrend: _numberList(trendMap['vo2Max']),
    );
  }

  final String source;
  final String date;
  final bool finalized;
  final DateTime syncedAt;
  final int steps;
  final double distanceKm;
  final int calories;
  final int activeMinutes;
  final int? sedentaryMinutes;
  final int? mindfulnessMinutes;
  final int? activeZoneMinutes;
  final FitbitActiveZoneMinutes? activeZoneMinutesByZone;
  final int? restingHeartRate;
  final FitbitHeartSample? latestHeartRate;
  final int? sleepMinutes;
  final int? sleepEfficiency;
  final FitbitSleepDetails? sleepDetails;
  final FitbitOxygenSaturation? oxygenSaturation;
  final double? heartRateVariabilityMs;
  final double? respiratoryRate;
  final FitbitSkinTemperature? skinTemperature;
  final FitbitVo2Max? vo2Max;
  final List<FitbitWorkout> workouts;
  final List<FitbitHeartPoint> heartProfile;
  final List<FitbitSleepStage> sleepStages;
  final List<double> stepsTrend;
  final List<double> distanceTrend;
  final List<double> caloriesTrend;
  final List<double> activeMinutesTrend;
  final List<double> sedentaryMinutesTrend;
  final List<double> activeZoneMinutesTrend;
  final List<double> restingHeartRateTrend;
  final List<double> sleepMinutesTrend;
  final List<double> oxygenSaturationTrend;
  final List<double> heartRateVariabilityTrend;
  final List<double> respiratoryRateTrend;
  final List<double> skinTemperatureTrend;
  final List<double> vo2MaxTrend;
}

class FitbitActiveZoneMinutes {
  const FitbitActiveZoneMinutes({
    required this.fatBurn,
    required this.cardio,
    required this.peak,
  });

  factory FitbitActiveZoneMinutes.fromJson(Map<String, Object?> json) =>
      FitbitActiveZoneMinutes(
        fatBurn: _requiredInt(json, 'fatBurn'),
        cardio: _requiredInt(json, 'cardio'),
        peak: _requiredInt(json, 'peak'),
      );

  final int fatBurn;
  final int cardio;
  final int peak;
}

class FitbitWorkout {
  const FitbitWorkout({
    required this.type,
    required this.name,
    required this.startTime,
    required this.activeMinutes,
    required this.calories,
    required this.distanceKm,
    required this.averageHeartRate,
  });

  factory FitbitWorkout.fromJson(Map<String, Object?> json) => FitbitWorkout(
    type: _requiredString(json, 'type'),
    name: json['name'] as String?,
    startTime: DateTime.parse(_requiredString(json, 'startTime')),
    activeMinutes: _requiredInt(json, 'activeMinutes'),
    calories: _nullableInt(json['calories']),
    distanceKm: _nullableDouble(json['distanceKm']),
    averageHeartRate: _nullableInt(json['averageHeartRate']),
  );

  final String type;
  final String? name;
  final DateTime startTime;
  final int activeMinutes;
  final int? calories;
  final double? distanceKm;
  final int? averageHeartRate;
}

class FitbitSleepDetails {
  const FitbitSleepDetails({
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.processed,
    required this.stagesStatus,
    required this.minutesInSleepPeriod,
    required this.minutesAwake,
    required this.minutesToFallAsleep,
    required this.minutesAfterWakeUp,
    required this.stageMinutes,
    required this.shortAwakenings,
  });

  factory FitbitSleepDetails.fromJson(Map<String, Object?> json) {
    final rawStageMinutes = json['stageMinutes'];
    final stageMinutes = rawStageMinutes is Map<String, Object?>
        ? rawStageMinutes
        : const <String, Object?>{};
    return FitbitSleepDetails(
      startTime: _nullableDateTime(json['startTime']),
      endTime: _nullableDateTime(json['endTime']),
      type: json['type'] as String?,
      processed: json['processed'] as bool?,
      stagesStatus: json['stagesStatus'] as String?,
      minutesInSleepPeriod: _nullableInt(json['minutesInSleepPeriod']) ?? 0,
      minutesAwake: _nullableInt(json['minutesAwake']) ?? 0,
      minutesToFallAsleep: _nullableInt(json['minutesToFallAsleep']) ?? 0,
      minutesAfterWakeUp: _nullableInt(json['minutesAfterWakeUp']) ?? 0,
      stageMinutes: FitbitSleepStageMinutes(
        awake: _nullableInt(stageMinutes['awake']) ?? 0,
        light: _nullableInt(stageMinutes['light']) ?? 0,
        deep: _nullableInt(stageMinutes['deep']) ?? 0,
        rem: _nullableInt(stageMinutes['rem']) ?? 0,
        asleep: _nullableInt(stageMinutes['asleep']) ?? 0,
        restless: _nullableInt(stageMinutes['restless']) ?? 0,
      ),
      shortAwakenings: _objectList(
        json['shortAwakenings'],
        FitbitSleepAwakening.fromJson,
      ),
    );
  }

  final DateTime? startTime;
  final DateTime? endTime;
  final String? type;
  final bool? processed;
  final String? stagesStatus;
  final int minutesInSleepPeriod;
  final int minutesAwake;
  final int minutesToFallAsleep;
  final int minutesAfterWakeUp;
  final FitbitSleepStageMinutes stageMinutes;
  final List<FitbitSleepAwakening> shortAwakenings;
}

class FitbitSleepStageMinutes {
  const FitbitSleepStageMinutes({
    required this.awake,
    required this.light,
    required this.deep,
    required this.rem,
    required this.asleep,
    required this.restless,
  });

  final int awake;
  final int light;
  final int deep;
  final int rem;
  final int asleep;
  final int restless;
}

class FitbitSleepAwakening {
  const FitbitSleepAwakening({required this.startTime, required this.endTime});

  factory FitbitSleepAwakening.fromJson(Map<String, Object?> json) =>
      FitbitSleepAwakening(
        startTime: DateTime.parse(_requiredString(json, 'startTime')),
        endTime: DateTime.parse(_requiredString(json, 'endTime')),
      );

  final DateTime startTime;
  final DateTime endTime;
}

class FitbitVo2Max {
  const FitbitVo2Max({
    required this.value,
    required this.measuredDate,
    required this.cardioFitnessLevel,
    required this.estimated,
  });

  factory FitbitVo2Max.fromJson(Map<String, Object?> json) => FitbitVo2Max(
    value: _requiredNumber(json, 'value').toDouble(),
    measuredDate: _requiredString(json, 'measuredDate'),
    cardioFitnessLevel: json['cardioFitnessLevel'] as String?,
    estimated: json['estimated'] == true,
  );

  final double value;
  final String measuredDate;
  final String? cardioFitnessLevel;
  final bool estimated;
}

class FitbitOxygenSaturation {
  const FitbitOxygenSaturation({
    required this.average,
    required this.minimum,
    required this.maximum,
  });

  factory FitbitOxygenSaturation.fromJson(Map<String, Object?> json) =>
      FitbitOxygenSaturation(
        average: _requiredNumber(json, 'average').toDouble(),
        minimum: _nullableDouble(json['minimum']),
        maximum: _nullableDouble(json['maximum']),
      );

  final double average;
  final double? minimum;
  final double? maximum;
}

class FitbitSkinTemperature {
  const FitbitSkinTemperature({
    required this.nightlyCelsius,
    required this.baselineCelsius,
  });

  factory FitbitSkinTemperature.fromJson(Map<String, Object?> json) =>
      FitbitSkinTemperature(
        nightlyCelsius: _requiredNumber(json, 'nightlyCelsius').toDouble(),
        baselineCelsius: _nullableDouble(json['baselineCelsius']),
      );

  final double nightlyCelsius;
  final double? baselineCelsius;
}

class FitbitHeartSample {
  const FitbitHeartSample({
    required this.measuredAt,
    required this.beatsPerMinute,
  });

  static FitbitHeartSample? fromJson(Map<String, Object?> json) {
    final measuredAt = _nullableDateTime(json['measuredAt']);
    final bpm = _nullableInt(json['beatsPerMinute']);
    if (measuredAt == null || bpm == null || bpm <= 0) return null;
    return FitbitHeartSample(measuredAt: measuredAt, beatsPerMinute: bpm);
  }

  final DateTime measuredAt;
  final int beatsPerMinute;
}

class FitbitHeartPoint {
  const FitbitHeartPoint({
    required this.startTime,
    required this.average,
    required this.minimum,
    required this.maximum,
  });

  factory FitbitHeartPoint.fromJson(Map<String, Object?> json) =>
      FitbitHeartPoint(
        startTime: DateTime.parse(_requiredString(json, 'startTime')),
        average: _requiredNumber(json, 'average').toDouble(),
        minimum: _requiredNumber(json, 'minimum').toDouble(),
        maximum: _requiredNumber(json, 'maximum').toDouble(),
      );

  final DateTime startTime;
  final double average;
  final double minimum;
  final double maximum;
}

class FitbitSleepStage {
  const FitbitSleepStage({
    required this.startTime,
    required this.endTime,
    required this.type,
  });

  factory FitbitSleepStage.fromJson(Map<String, Object?> json) =>
      FitbitSleepStage(
        startTime: DateTime.parse(_requiredString(json, 'startTime')),
        endTime: DateTime.parse(_requiredString(json, 'endTime')),
        type: _requiredString(json, 'type'),
      );

  final DateTime startTime;
  final DateTime endTime;
  final String type;
}

class FitbitStatus {
  const FitbitStatus({
    required this.configured,
    required this.connection,
    required this.deviceName,
    required this.day,
  });

  factory FitbitStatus.fromJson(Map<String, Object?> json) {
    final rawDay = json['day'];
    return FitbitStatus(
      configured: json['configured'] == true,
      connection: _requiredString(json, 'connection'),
      deviceName: json['deviceName'] as String?,
      day: rawDay is Map<String, Object?> ? FitbitDay.fromJson(rawDay) : null,
    );
  }

  final bool configured;
  final String connection;
  final String? deviceName;
  final FitbitDay? day;
  bool get isConnected => connection == 'CONNECTED';
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key non valido');
  }
  return value;
}

num _requiredNumber(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('$key non valido');
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) =>
    _requiredNumber(json, key).round();

int? _nullableInt(Object? value) => value is num ? value.round() : null;

double? _nullableDouble(Object? value) =>
    value is num ? value.toDouble() : null;

DateTime? _nullableDateTime(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

List<double> _numberList(Object? value) => value is List
    ? value
          .whereType<num>()
          .map((item) => item.toDouble())
          .toList(growable: false)
    : const [];

List<T> _objectList<T>(
  Object? value,
  T Function(Map<String, Object?> json) decode,
) => value is List
    ? value
          .whereType<Map<String, Object?>>()
          .map(decode)
          .toList(growable: false)
    : const [];
