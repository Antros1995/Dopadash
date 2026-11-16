import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/storage/key_value_store.dart';
import '../domain/market_models.dart';
import 'market_repository.dart';

/// Shared read cache. Watchlist mutations never reach the remote repository.
class LocalMarketRepository implements MarketRepository {
  LocalMarketRepository(this.source, this.store, this.scope);
  final MarketRepository source;
  final KeyValueStore store;
  final String scope;
  final Map<String, (DateTime, MarketSeries)> _cache = {};
  final Map<String, Future<MarketSeries>> _pending = {};
  @override
  Future<List<MarketInstrument>> loadWatchlist() async {
    final raw = await store.read('market.watchlist.v1.$scope');
    if (raw == null) return source.loadWatchlist();
    return [
      for (final j in jsonDecode(raw))
        if (MarketInstrument.fromJson(j) case final MarketInstrument instrument)
          instrument,
    ];
  }

  @override
  Future<void> saveWatchlist(List<MarketInstrument> instruments) => store.write(
    'market.watchlist.v1.$scope',
    jsonEncode(instruments.map((i) => i.toJson()).toList()),
  );
  @override
  Future<MarketSeries> fetchSeries(
    MarketInstrument instrument,
    MarketPeriod period,
  ) {
    final key = '${instrument.symbol}:${period.apiValue}';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) <
            (period == MarketPeriod.day
                ? const Duration(seconds: 25)
                : const Duration(minutes: 10))) {
      return Future.value(cached.$2);
    }
    return _pending.putIfAbsent(key, () => _fetch(instrument, period, key));
  }

  Future<MarketSeries> _fetch(
    MarketInstrument i,
    MarketPeriod p,
    String key,
  ) async {
    try {
      final s = ['localhost', '127.0.0.1'].contains(Uri.base.host)
          ? await _localSeries(i, p)
          : await source.fetchSeries(i, p);
      final points =
          s.points.where((p) => p.close.isFinite && p.close > 0).toList()
            ..sort((a, b) => a.time.compareTo(b.time));
      if (points.isEmpty || s.symbol.toUpperCase() != i.symbol.toUpperCase()) {
        throw const MarketFailure(MarketFailureKind.invalidResponse);
      }
      final clean = MarketSeries(
        symbol: s.symbol,
        name: s.name,
        currency: s.currency.toUpperCase(),
        exchange: s.exchange,
        previousClose: s.previousClose,
        points: points,
        updatedAt: s.updatedAt,
      );
      _cache[key] = (DateTime.now(), clean);
      return clean;
    } finally {
      _pending.remove(key);
    }
  }

  @override
  void dispose() {
    _cache.clear();
  }

  Future<MarketSeries> _localSeries(MarketInstrument i, MarketPeriod p) async {
    final uri = Uri.base
        .resolve('/api/local/markets')
        .replace(queryParameters: {'symbol': i.symbol, 'period': p.apiValue});
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const MarketFailure(MarketFailureKind.unavailable);
    }
    final j = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketSeries(
      symbol: j['symbol'],
      name: j['name'],
      currency: j['currency'],
      exchange: j['exchange'],
      previousClose: (j['previousClose'] as num?)?.toDouble(),
      points: [
        for (final v in j['points'])
          MarketPoint(
            time: DateTime.fromMillisecondsSinceEpoch(
              (v['timestamp'] as num).toInt() * 1000,
            ),
            close: (v['close'] as num).toDouble(),
          ),
      ],
      updatedAt: DateTime.parse(j['updatedAt']),
    );
  }
}
