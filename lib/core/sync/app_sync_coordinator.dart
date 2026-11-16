import 'dart:async';
import 'package:flutter/widgets.dart';
import 'app_sync_events.dart';

/// Recovers a long-lived tab without reloading the application or its forms.
class AppSyncCoordinator with WidgetsBindingObserver {
  AppSyncCoordinator({
    required this.ensureSession,
    required this.synchronize,
    Stream<void>? recoveryEvents,
    this.interval = const Duration(minutes: 1),
  }) : _events = recoveryEvents ?? appSyncEvents();

  final Future<void> Function() ensureSession, synchronize;
  final Stream<void> _events;
  final Duration interval;
  StreamSubscription<void>? _subscription;
  Timer? _timer, _debounce, _retry;
  bool _active = true, _disposed = false, _started = false;
  Future<void>? _pending;
  bool _queued = false;

  void start() {
    if (_disposed || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _subscription = _events.listen((_) => _schedule(), onError: (Object _) {});
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  void _schedule() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) _schedule();
  }

  Future<void> refresh() {
    if (_disposed || !_active) return Future.value();
    if (_pending != null) {
      _queued = true;
      return _pending!;
    }
    return _pending = _refresh().whenComplete(() => _pending = null);
  }

  Future<void> _refresh() async {
    do {
      _queued = false;
      try {
        // Restore authentication before starting any parallel data requests.
        await ensureSession().timeout(const Duration(seconds: 30));
        if (_disposed || !_active) return;
        await synchronize().timeout(const Duration(minutes: 2));
        _retry?.cancel();
        _retry = null;
      } on Object catch (error) {
        debugPrint('Background sync will retry (${error.runtimeType})');
        if (!_disposed && _retry == null) {
          _retry = Timer(const Duration(seconds: 10), () {
            _retry = null;
            unawaited(refresh());
          });
        }
        return;
      }
    } while (_queued && !_disposed && _active);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _debounce?.cancel();
    _retry?.cancel();
    unawaited(_subscription?.cancel());
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}
