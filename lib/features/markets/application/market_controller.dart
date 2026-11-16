import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/market_repository.dart';
import '../domain/market_currency.dart';
import '../domain/market_models.dart';

class MarketController extends ChangeNotifier {
  MarketController({required this.repository});

  final MarketRepository repository;
  List<MarketInstrument> _instruments = const [];
  final Map<String, MarketPeriod> _periods = {};
  final Map<String, MarketSeries> _series = {};
  final Set<String> _loading = {};
  final Map<String, MarketFailureKind> _errors = {};
  String _currency = 'EUR';
  bool _initializing = true;
  bool _saving = false;
  Timer? _refreshTimer;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  List<MarketInstrument> get instruments => List.unmodifiable(_instruments);
  bool get initializing => _initializing;
  bool get saving => _saving;
  String get currency => _currency;

  Future<void> setCurrency(String currency) async {
    if (!['EUR', 'USD'].contains(currency) || currency == _currency) return;
    _currency = currency;
    _series.clear();
    notifyListeners();
    await refreshAll();
  }

  Future<MarketSeries> fetchDisplaySeries(
    MarketInstrument instrument,
    MarketPeriod period, {
    String? currency,
  }) async {
    final target = currency ?? _currency;
    final source = await repository.fetchSeries(instrument, period);
    if (source.currency == target) return source;
    // EURUSD=X is quoted as USD per EUR, in both local and Worker feeds.
    final euroDollar = ['EUR', 'USD'].contains(source.currency);
    final symbol = euroDollar ? 'EURUSD=X' : '${source.currency}$target=X';
    final rates = await repository.fetchSeries(
      MarketInstrument(symbol: symbol, name: symbol),
      // Include the previous session and weekends for 24-hour crypto prices.
      period == MarketPeriod.day ? MarketPeriod.week : period,
    );
    if (rates.currency != (euroDollar ? 'USD' : target)) {
      throw const MarketFailure(MarketFailureKind.invalidResponse);
    }
    return convertMarketCurrency(
      source,
      rates,
      currency: target,
      inverse: euroDollar && target == 'EUR',
    );
  }

  MarketPeriod periodFor(String symbol) => _periods[symbol] ?? MarketPeriod.day;
  MarketSeries? seriesFor(String symbol) => _series[symbol];
  bool isLoading(String symbol) => _loading.contains(symbol);
  MarketFailureKind? errorFor(String symbol) => _errors[symbol];

  Future<void> load() async {
    _initializing = true;
    notifyListeners();
    try {
      _instruments = await repository.loadWatchlist();
      for (final instrument in _instruments) {
        _periods.putIfAbsent(instrument.symbol, () => MarketPeriod.day);
      }
    } finally {
      _initializing = false;
      notifyListeners();
    }
    await refreshAll();
    if (_disposed) return;
    _refreshTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refreshAll()),
    );
  }

  Future<void> refreshAll() async {
    await Future.wait([for (final item in _instruments) refresh(item.symbol)]);
  }

  Future<void> refresh(String symbol) async {
    final instrument = _instruments
        .where((item) => item.symbol == symbol)
        .firstOrNull;
    if (instrument == null) return;
    if (_loading.contains(symbol)) return;
    _loading.add(symbol);
    _errors.remove(symbol);
    notifyListeners();
    try {
      // A selector change during a request must never restore the old currency.
      while (!_disposed) {
        final target = _currency;
        final series = await fetchDisplaySeries(
          instrument,
          periodFor(symbol),
          currency: target,
        );
        if (target != _currency) continue;
        _series[symbol] = series;
        break;
      }
    } on MarketFailure catch (error) {
      _errors[symbol] = error.kind;
    } on Object {
      _errors[symbol] = MarketFailureKind.unavailable;
    } finally {
      _loading.remove(symbol);
      notifyListeners();
    }
  }

  Future<void> setPeriod(String symbol, MarketPeriod period) async {
    if (periodFor(symbol) == period) return;
    _periods[symbol] = period;
    notifyListeners();
    await refresh(symbol);
  }

  Future<void> add({
    required String symbol,
    String? name,
    String? category,
  }) async {
    final normalized = normalizeMarketSymbol(symbol);
    if (!RegExp(r'^[A-Z0-9^=._-]{1,24}$').hasMatch(normalized)) {
      throw const MarketFailure(MarketFailureKind.symbolNotFound);
    }
    if (_instruments.any((item) => item.symbol == normalized)) return;
    final temporary = MarketInstrument(
      symbol: normalized,
      name: name?.trim().isNotEmpty == true ? name!.trim() : normalized,
    );
    _loading.add(normalized);
    notifyListeners();
    try {
      final series = await repository.fetchSeries(temporary, MarketPeriod.day);
      final instrument = MarketInstrument(
        symbol: normalized,
        assetCategory: category,
        name: name?.trim().isNotEmpty == true ? name!.trim() : series.name,
      );
      _instruments = [..._instruments, instrument];
      _periods[normalized] = MarketPeriod.day;
      await _save();
    } finally {
      _loading.remove(normalized);
      notifyListeners();
    }
    await refresh(normalized);
  }

  Future<void> remove(String symbol) async {
    _instruments = [
      for (final item in _instruments)
        if (item.symbol != symbol) item,
    ];
    _series.remove(symbol);
    _periods.remove(symbol);
    _errors.remove(symbol);
    notifyListeners();
    await _save();
  }

  Future<void> move(String symbol, int offset) async {
    final index = _instruments.indexWhere((item) => item.symbol == symbol);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= _instruments.length) return;
    final updated = [..._instruments];
    final item = updated.removeAt(index);
    updated.insert(target, item);
    _instruments = updated;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    _saving = true;
    notifyListeners();
    try {
      await repository.saveWatchlist(_instruments);
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
