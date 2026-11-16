import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';
import '../data/body_statistics_repository.dart';
import '../domain/body_statistics.dart';
import '../domain/perception_statistics.dart';

class BodyStatisticsController extends ChangeNotifier {
  BodyStatisticsController({
    required this.repository,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final BodyStatisticsRepository repository;
  final DateTime Function() clock;
  List<BodyDay> days = [];
  List<PerceptionEntry> perceptions = [];
  String perceptionEmotion = 'all';
  String? perceptionError;
  bool perceptionsLoading = false;
  List<BodyExperiment> experiments = [];
  List<ExperimentLog> logs = [];
  BodyPeriod period = BodyPeriod.month;
  BodyRange? customRange, customComparison;
  DateTime? anchor;
  String section = 'Panoramica';
  bool compare = true,
      moving = true,
      weeklySleep = false,
      sleepStages = true,
      activitySteps = false,
      averageHeartDay = false,
      showArchived = false;
  BodyMetric heartMetric = BodyMetric.restingHr,
      experimentMetric = BodyMetric.calm;
  String? selectedId;
  Set<String> excludedFactors = {};
  bool loading = false, syncing = false, saving = false, loaded = false;
  bool logsLoading = false;
  bool recovering = false;
  bool _cancelRecovery = false;
  int recoveredDays = 0, recoveryTotal = 0;
  Timer? _refreshTimer;
  String? error, syncError, saveError;
  bool _disposed = false;
  int _selectionVersion = 0;
  Future<void> _preferenceQueue = Future.value();
  DateTime get today => statsDate(clock());
  BodyExperiment? get selected {
    for (final e in experiments) {
      if (e.id == selectedId) return e;
    }
    return null;
  }

  BodyRange get range {
    if (period == BodyPeriod.custom && customRange != null) return customRange!;
    final end = anchor ?? today;
    if (period == BodyPeriod.all) {
      final available =
          (section == 'Percezione'
                  ? perceptions.map((entry) => entry.date)
                  : days.map((day) => day.date))
              .where((date) => !date.isAfter(end));
      final start = available.fold<DateTime>(
        end,
        (first, date) => date.isBefore(first) ? date : first,
      );
      return BodyRange(start, end);
    }
    return BodyRange(
      end.subtract(Duration(days: (period.days ?? 30) - 1)),
      end,
    );
  }

  BodyRange? get comparisonRange =>
      compare ? customComparison ?? range.previous : null;
  Map<String, BodyDay> get _byDate => {
    for (final d in days) statsKey(d.date): d,
  };
  List<double?> series(BodyMetric metric, BodyRange r) {
    final byDate = _byDate;
    return r.dates.map((d) => byDate[statsKey(d)]?.value(metric)).toList();
  }

  BodySummary summary(BodyMetric metric, BodyRange r) =>
      BodySummary(series(metric, r), r.days);
  ExperimentComparison? get analysis => selected == null
      ? null
      : ExperimentComparison(
          experiment: selected!,
          days: days,
          logs: logs,
          perceptions: perceptions,
          today: today,
          excludedFactors: excludedFactors,
        );
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (loading || _disposed) return;
    loading = true;
    error = null;
    _emit();
    try {
      final preferences = await repository.loadPreferences().timeout(
        const Duration(seconds: 20),
      );
      days = await repository.loadDays().timeout(const Duration(seconds: 30));
      experiments = await repository.loadExperiments().timeout(
        const Duration(seconds: 20),
      );
      await loadPerceptions();
      if (!loaded) _restore(preferences);
      loaded = true;
      final id = selectedId;
      if (id != null && selected != null) {
        await selectExperiment(id, persist: false);
      }
    } on Object catch (e) {
      error = message(e);
    } finally {
      loading = false;
      _emit();
    }
  }

  Future<void> loadPerceptions() async {
    if (perceptionsLoading || _disposed) return;
    perceptionsLoading = true;
    perceptionError = null;
    _emit();
    try {
      final result = await repository.loadPerceptions().timeout(
        const Duration(seconds: 30),
      );
      if (!_disposed) perceptions = result;
    } on Object catch (e) {
      perceptionError =
          e is PostgrestException && (e.code == '42P01' || e.code == 'PGRST205')
          ? 'Il diario delle emozioni non è disponibile in Supabase.'
          : message(e);
    } finally {
      perceptionsLoading = false;
      _emit();
    }
  }

  Future<void> refresh() async {
    if (syncing || _disposed) return;
    syncing = true;
    syncError = null;
    _emit();
    try {
      await repository.syncHistory().timeout(const Duration(seconds: 60));
      days = await repository.loadDays().timeout(const Duration(seconds: 30));
      _lastHistorySync = clock();
    } on Object catch (e) {
      syncError = message(e);
    } finally {
      syncing = false;
      _emit();
    }
  }

  void setActive(bool active) {
    _refreshTimer?.cancel();
    if (active) {
      _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (loaded && !loading && !syncing && !saving && !recovering) {
          unawaited(synchronize());
        }
      });
    }
  }

  DateTime? _lastHistorySync;
  Future<void> synchronize() async {
    if (loading || syncing || saving || recovering || _disposed) {
      return;
    }
    if (!loaded) {
      await load();
      if (!loaded || _disposed) return;
    }
    if (_lastHistorySync == null ||
        clock().difference(_lastHistorySync!) >= const Duration(minutes: 5) ||
        syncError != null) {
      await refresh();
      if (syncError == null) _lastHistorySync = clock();
    }
    if (!_disposed && !saving && !recovering) await load();
  }

  Future<void> recoverMissingDays() async {
    if (recovering || syncing) return;
    final byDate = _byDate;
    // In Attività si richiedono di nuovo anche i giorni salvati senza passi:
    // capita quando la giornata è stata letta prima che l'orologio si
    // sincronizzasse.
    bool missing(DateTime d) {
      final day = byDate[statsKey(d)];
      return day == null ||
          (section == 'Attività' &&
              d.isBefore(today) &&
              day.value(BodyMetric.steps) == null);
    }

    final dates = <DateTime>{
      if (section == 'Esperimenti' && selected != null) ...[
        ...selected!.baseline.dates,
        ...selected!.range.dates,
      ] else ...[
        ...range.dates,
        ...?comparisonRange?.dates,
      ],
    }.where((d) => !d.isAfter(today) && missing(d)).toList()..sort();
    if (dates.isEmpty) return;
    recovering = true;
    _cancelRecovery = false;
    recoveredDays = 0;
    recoveryTotal = dates.length;
    syncError = null;
    _emit();
    try {
      await repository.recoverDays(
        dates,
        cancelled: () => _disposed || _cancelRecovery,
        onProgress: (done, total) {
          recoveredDays = done;
          recoveryTotal = total;
          _emit();
        },
      );
    } on Object catch (e) {
      syncError = message(e);
    } finally {
      try {
        if (!_disposed) days = await repository.loadDays();
      } on Object catch (e) {
        syncError = message(e);
      }
      recovering = false;
      _emit();
    }
  }

  void cancelRecovery() {
    _cancelRecovery = true;
    _emit();
  }

  void change(VoidCallback update) {
    update();
    _emit();
    unawaited(persist());
  }

  Future<void> persist() {
    final snapshot = preferences;
    _preferenceQueue = _preferenceQueue.then((_) async {
      try {
        await repository.savePreferences(snapshot);
        saveError = null;
      } on Object catch (e) {
        saveError = message(e);
      }
      _emit();
    });
    return _preferenceQueue;
  }

  Map<String, dynamic> get preferences => {
    'period': period.name,
    'anchor': anchor == null ? null : statsKey(anchor!),
    'customRange': customRange?.toJson(),
    'customComparison': customComparison?.toJson(),
    'compare': compare,
    'moving': moving,
    'section': section,
    'selectedId': selectedId,
    'excludedFactors': excludedFactors.toList(),
    'heartMetric': heartMetric.key,
    'experimentMetric': experimentMetric.key,
    'perceptionEmotion': perceptionEmotion,
    'weeklySleep': weeklySleep,
    'sleepStages': sleepStages,
    'activitySteps': activitySteps,
    'averageHeartDay': averageHeartDay,
    'showArchived': showArchived,
  };
  void _restore(Map<String, dynamic> p) {
    try {
      period = BodyPeriod.values.byName(p['period'] ?? 'month');
      anchor = p['anchor'] == null ? null : statsParse(p['anchor']);
      customRange = p['customRange'] == null
          ? null
          : BodyRange.fromJson(
              (p['customRange'] as Map).cast<String, dynamic>(),
            );
      customComparison = p['customComparison'] == null
          ? null
          : BodyRange.fromJson(
              (p['customComparison'] as Map).cast<String, dynamic>(),
            );
      compare = p['compare'] as bool? ?? true;
      moving = p['moving'] as bool? ?? true;
      section = p['section'] as String? ?? 'Panoramica';
      selectedId = p['selectedId'] as String?;
      excludedFactors =
          (p['excludedFactors'] as List?)?.cast<String>().toSet() ?? {};
      heartMetric = BodyMetric.parse(p['heartMetric'] ?? 'restingHeartRate');
      experimentMetric = BodyMetric.parse(p['experimentMetric'] ?? 'calm');
      perceptionEmotion = p['perceptionEmotion'] as String? ?? 'all';
      weeklySleep = p['weeklySleep'] == true;
      sleepStages = p['sleepStages'] != false;
      activitySteps = p['activitySteps'] == true;
      averageHeartDay = p['averageHeartDay'] == true;
      showArchived = p['showArchived'] == true;
    } on Object {
      saveError =
          'Alcune preferenze non sono valide. Seleziona nuovamente i filtri.';
    }
  }

  Future<void> selectExperiment(String id, {bool persist = true}) async {
    final version = ++_selectionVersion;
    selectedId = id;
    logsLoading = true;
    logs = [];
    error = null;
    if (selected != null && !selected!.metrics.contains(experimentMetric)) {
      experimentMetric = selected!.primary;
    }
    _emit();
    try {
      final result = await repository.loadLogs(id);
      if (version == _selectionVersion && !_disposed) logs = result;
    } on Object catch (e) {
      if (version == _selectionVersion) error = message(e);
    }
    if (version == _selectionVersion) logsLoading = false;
    if (persist) await this.persist();
    _emit();
  }

  Future<bool> saveExperiment(BodyExperiment experiment) async {
    saving = true;
    saveError = null;
    _emit();
    try {
      final saved = await repository.saveExperiment(experiment);
      experiments = await repository.loadExperiments();
      section = 'Esperimenti';
      await selectExperiment(saved.id!);
      return true;
    } on Object catch (e) {
      saveError = message(e);
      return false;
    } finally {
      saving = false;
      _emit();
    }
  }

  Future<bool> saveLog(ExperimentLog log, {bool delete = false}) async {
    saving = true;
    saveError = null;
    _emit();
    try {
      if (delete) {
        await repository.deleteLog(log);
      } else {
        await repository.saveLog(log);
      }
      if (selectedId == log.experimentId) {
        await selectExperiment(log.experimentId, persist: false);
      }
      return true;
    } on Object catch (e) {
      saveError = message(e);
      return false;
    } finally {
      saving = false;
      _emit();
    }
  }

  static String message(Object e) {
    if (e is PostgrestException) {
      if (e.code == '42P01' || e.code == 'PGRST205') {
        return 'Schema Statistiche non disponibile: applicare la migrazione 20261017_body_statistics.sql in Supabase.';
      }
      if (e.code == '42501' || e.code == 'PGRST301') {
        return 'Accesso non disponibile: verifica la sessione e le policy Supabase.';
      }
      return 'Supabase non ha completato l’operazione (${e.code ?? 'errore'}). Riprova.';
    }
    if (e is ArgumentError) return e.message.toString();
    if (e is StateError) return e.message;
    return 'Operazione non riuscita. Controlla la connessione e riprova.';
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _selectionVersion++;
    super.dispose();
  }
}
