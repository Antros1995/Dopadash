import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/expense_repository.dart';
import '../domain/expense_workbook.dart';

const initialExpenseLink = String.fromEnvironment('EXPENSES_ONEDRIVE_URL');

class ExpenseController extends ChangeNotifier {
  ExpenseController({required this.repository});
  final ExpenseRepository repository;
  ExpenseSettings settings = const ExpenseSettings();
  ExpenseData? data;
  String? error, settingsError;
  bool loading = false, saving = false, _disposed = false;
  StreamSubscription<ExpenseSettings>? _subscription;
  Timer? _autoRefresh;
  Uint8List? _lastBytes;
  DateTime? _lastAttempt;
  bool _loaded = false, _active = false;
  int _request = 0;
  Completer<void>? _inFlight;
  String? _inFlightSource;
  int _settingsVersion = 0;
  bool _feedFailed = false;
  static const syncInterval = Duration(seconds: 20);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String get sourceUrl =>
      settings.sourceUrl.isEmpty ? initialExpenseLink : settings.sourceUrl;
  void setActive(bool value) {
    if (_disposed || _active == value) return;
    _active = value;
    _autoRefresh?.cancel();
    if (!value) return;
    _autoRefresh = Timer.periodic(syncInterval, (_) {
      if (_inFlight == null && sourceUrl.isNotEmpty) {
        unawaited(refresh(background: true));
      }
    });
    if (_loaded &&
        _inFlight == null &&
        sourceUrl.isNotEmpty &&
        (_lastAttempt == null ||
            DateTime.now().difference(_lastAttempt!) >
                const Duration(seconds: 5))) {
      unawaited(refresh(background: data != null));
    }
  }

  Future<void> load({bool background = false}) async {
    if (_disposed || saving) return;
    final version = _settingsVersion;
    try {
      final remote = await repository.loadSettings().timeout(
        const Duration(seconds: 20),
      );
      if (_disposed || version != _settingsVersion) return;
      settings = remote;
      settingsError = null;
      if (_feedFailed) {
        await _subscription?.cancel();
        _subscription = null;
        _feedFailed = false;
      }
      _subscription ??= repository.watchSettings().listen(
        (value) {
          if (_disposed || saving) return;
          _settingsVersion++;
          final changed = settings.sourceUrl != value.sourceUrl;
          settings = value;
          _notify();
          if (changed && value.sourceUrl.isNotEmpty && !saving) {
            unawaited(refresh());
          }
        },
        onError: (Object _) {
          _feedFailed = true;
          settingsError = 'Impostazioni server non disponibili.';
          _notify();
        },
        onDone: () => _feedFailed = true,
      );
    } on Object {
      settingsError =
          'Salvataggio su server non disponibile: applica la migrazione Spese in Supabase.';
    }
    _loaded = true;
    if (sourceUrl.isNotEmpty) {
      await refresh(background: background && data != null);
    } else {
      _notify();
    }
  }

  Future<void> refresh({String? link, bool background = false}) async {
    if (_disposed) return;
    final source = link ?? sourceUrl;
    if (_inFlight != null && _inFlightSource == source) {
      if (!background && !loading) {
        loading = true;
        _notify();
      }
      return _inFlight!.future;
    }
    final completion = Completer<void>();
    _inFlight = completion;
    _inFlightSource = source;
    final request = ++_request;
    final previousAttempt = _lastAttempt;
    _lastAttempt = DateTime.now();
    final dayChanged =
        previousAttempt == null ||
        previousAttempt.year != _lastAttempt!.year ||
        previousAttempt.month != _lastAttempt!.month ||
        previousAttempt.day != _lastAttempt!.day;
    final previousError = error;
    var changed = false;
    loading = !background || data == null;
    error = null;
    if (loading) _notify();
    try {
      final bytes = await repository
          .fetchWorkbook(source)
          .timeout(const Duration(seconds: 90));
      if (!_disposed && request == _request && !listEquals(_lastBytes, bytes)) {
        final value = readExpenseData(ExpenseWorkbook.decode(bytes));
        _lastBytes = bytes;
        data = value;
        changed = true;
      }
    } on Object catch (e) {
      if (request == _request) {
        error = '$e'
            .replaceFirst('Bad state: ', '')
            .replaceFirst('FormatException: ', '');
      }
    } finally {
      if (request == _request) {
        final visibleLoading = loading;
        loading = false;
        _inFlight = null;
        _inFlightSource = null;
        if (visibleLoading ||
            changed ||
            dayChanged ||
            previousError != null ||
            error != null) {
          _notify();
        }
      }
      completion.complete();
    }
  }

  Future<void> importBytes(Uint8List bytes, String name) async {
    ++_request;
    _inFlight = null;
    _inFlightSource = null;
    try {
      data = readExpenseData(ExpenseWorkbook.decode(bytes), sourceName: name);
      error = null;
      loading = false;
    } on Object catch (e) {
      error = '$e'.replaceFirst('FormatException: ', '');
    }
    _notify();
  }

  Future<bool> save({
    String? sourceUrl,
    String? month,
    double? limit,
    List<String>? chartMetrics,
  }) async {
    _settingsVersion++;
    saving = true;
    _notify();
    try {
      settings = await repository.saveSettings(
        sourceUrl: sourceUrl,
        month: month,
        limit: limit,
        chartMetrics: chartMetrics,
      );
      settingsError = null;
      return true;
    } on Object {
      settingsError =
          'Modifica non salvata sul server. Controlla la connessione e la migrazione Supabase.';
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _autoRefresh?.cancel();
    ++_request;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
