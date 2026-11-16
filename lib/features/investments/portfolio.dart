import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/storage/key_value_store.dart';
import '../markets/domain/market_models.dart';
import '../markets/data/local_market_repository.dart';

double money(double value) => (value * 100).round() / 100;

enum AssetKind { etf, stock, crypto, other }

extension AssetLabel on AssetKind {
  String get label => switch (this) {
    AssetKind.etf => 'ETF',
    AssetKind.stock => 'Azioni',
    AssetKind.crypto => 'Crypto',
    AssetKind.other => 'Altro',
  };
}

class Holding {
  const Holding({
    required this.symbol,
    required this.name,
    required this.kind,
    this.currency = 'EUR',
    this.openingQuantity = 0,
    this.openingCost = 0,
    this.openingDate,
    this.snapshotPrice,
    this.snapshotDate,
  });
  final String symbol, name, currency;
  final AssetKind kind;
  final double openingQuantity, openingCost;
  final DateTime? openingDate, snapshotDate;
  final double? snapshotPrice;
  MarketInstrument get instrument =>
      MarketInstrument(symbol: symbol, name: name);
  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'name': name,
    'kind': kind.name,
    'currency': currency,
    'quantity': openingQuantity,
    'cost': openingCost,
    'date': openingDate?.toIso8601String(),
    'price': snapshotPrice,
    'priceDate': snapshotDate?.toIso8601String(),
  };
  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
    symbol: j['symbol'],
    name: j['name'],
    kind: AssetKind.values.byName(j['kind']),
    currency: j['currency'],
    openingQuantity: (j['quantity'] as num).toDouble(),
    openingCost: (j['cost'] as num).toDouble(),
    openingDate: DateTime.tryParse(j['date'] ?? ''),
    snapshotPrice: (j['price'] as num?)?.toDouble(),
    snapshotDate: DateTime.tryParse(j['priceDate'] ?? ''),
  );
}

class PortfolioTrade {
  const PortfolioTrade({
    required this.id,
    required this.symbol,
    required this.date,
    required this.buy,
    required this.quantity,
    required this.price,
    required this.fees,
    required this.currency,
  });
  final String id, symbol, currency;
  final DateTime date;
  final bool buy;
  final double quantity, price, fees;
  Map<String, dynamic> toJson() => {
    'id': id,
    'symbol': symbol,
    'date': date.toIso8601String(),
    'buy': buy,
    'quantity': quantity,
    'price': price,
    'fees': fees,
    'currency': currency,
  };
  factory PortfolioTrade.fromJson(Map<String, dynamic> j) => PortfolioTrade(
    id: j['id'],
    symbol: j['symbol'],
    date: DateTime.parse(j['date']),
    buy: j['buy'],
    quantity: (j['quantity'] as num).toDouble(),
    price: (j['price'] as num).toDouble(),
    fees: (j['fees'] as num).toDouble(),
    currency: j['currency'],
  );
}

class Position {
  const Position(
    this.holding,
    this.quantity,
    this.cost,
    this.netCapital,
    this.realized,
  );
  final Holding holding;
  final double quantity, cost, netCapital, realized;
  double get averageCost => quantity <= 1e-9 ? 0 : cost / quantity;
}

Position calculatePosition(
  Holding h,
  List<PortfolioTrade> trades, {
  DateTime? at,
}) {
  var quantity =
      at == null || (h.openingDate != null && !h.openingDate!.isAfter(at))
      ? h.openingQuantity
      : 0.0;
  var cost = quantity > 0 ? h.openingCost : 0.0;
  var net = cost;
  var realized = 0.0;
  final ordered =
      trades
          .where(
            (t) => t.symbol == h.symbol && (at == null || !t.date.isAfter(at)),
          )
          .toList()
        ..sort((a, b) {
          final c = a.date.compareTo(b.date);
          return c == 0 ? a.id.compareTo(b.id) : c;
        });
  for (final t in ordered) {
    if (![t.quantity, t.price, t.fees].every((v) => v.isFinite) ||
        t.quantity <= 0 ||
        t.price <= 0 ||
        t.fees < 0) {
      throw ArgumentError(
        'Quantità e prezzo devono essere positivi; commissioni non negative.',
      );
    }
    if (t.currency != h.currency) {
      throw ArgumentError(
        'La valuta deve coincidere con quella dello strumento.',
      );
    }
    if (h.openingDate != null && t.date.isBefore(h.openingDate!)) {
      throw ArgumentError('Operazione precedente al saldo iniziale.');
    }
    if (t.buy) {
      final cash = money(t.quantity * t.price + t.fees);
      quantity += t.quantity;
      cost = money(cost + cash);
      net = money(net + cash);
    } else {
      if (t.quantity > quantity + 1e-8) {
        throw ArgumentError(
          'Vendita superiore alla quantità disponibile alla data indicata.',
        );
      }
      final removed = money(cost * t.quantity / quantity);
      final proceeds = money(t.quantity * t.price - t.fees);
      quantity -= t.quantity;
      cost = quantity.abs() < 1e-8 ? 0 : money(cost - removed);
      net = money(net - proceeds);
      realized = money(realized + proceeds - removed);
    }
  }
  return Position(h, quantity.abs() < 1e-8 ? 0 : quantity, cost, net, realized);
}

class PortfolioHistoryPoint {
  const PortfolioHistoryPoint(this.date, this.value, this.capital);
  final DateTime date;
  final double value, capital;
}

/// Daily closes aligned to calendar days. Last known close is carried at most
/// four days (weekends/holidays); never before its timestamp or before holdings.
List<PortfolioHistoryPoint> portfolioHistory(
  List<Holding> holdings,
  List<PortfolioTrade> trades,
  Map<String, MarketSeries> series,
  DateTime start,
  DateTime end,
) {
  if (holdings.any((h) => h.openingQuantity > 0 && h.openingDate == null)) {
    return [];
  }
  final result = <PortfolioHistoryPoint>[];
  for (
    var date = DateTime(start.year, start.month, start.day);
    !date.isAfter(end);
    date = DateTime(date.year, date.month, date.day + 1)
  ) {
    final cutoff = DateTime(date.year, date.month, date.day, 23, 59, 59);
    var value = 0.0, capital = 0.0;
    var covered = true, active = false;
    for (final h in holdings) {
      final p = calculatePosition(h, trades, at: cutoff);
      if (h.currency != 'EUR' && (p.quantity > 0 || p.netCapital != 0)) {
        covered = false;
        break;
      }
      capital += p.netCapital;
      if (p.quantity <= 0) continue;
      active = true;
      final s = series[h.symbol];
      if (s == null ||
          s.currency != h.currency ||
          s.symbol.toUpperCase() != h.symbol.toUpperCase()) {
        covered = false;
        break;
      }
      final prices = s.points.where(
        (v) =>
            !v.time.isAfter(cutoff) &&
            cutoff.difference(v.time).inHours <= 96 &&
            v.close.isFinite &&
            v.close > 0,
      );
      if (prices.isEmpty) {
        covered = false;
        break;
      }
      value += p.quantity * prices.last.close;
    }
    if (covered && (active || capital != 0)) {
      result.add(PortfolioHistoryPoint(date, money(value), money(capital)));
    }
  }
  return result;
}

class PortfolioController extends ChangeNotifier {
  PortfolioController({
    required this.store,
    required this.market,
    required this.scope,
  });
  final KeyValueStore store;
  final LocalMarketRepository market;
  final String scope;
  String get _key => 'portfolio.v1.$scope';
  List<Holding> holdings = [];
  List<PortfolioTrade> trades = [];
  final Map<String, MarketSeries> quotes = {}, historySeries = {};
  final Map<String, String> quoteErrors = {};
  bool loading = true, refreshing = false, saving = false, _disposed = false;
  String? error;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      final raw = await store.read(_key);
      if (raw == null) {
        holdings = [];
        await _persist(holdings, trades);
      } else {
        final j = jsonDecode(raw);
        holdings = [
          for (final h in j['holdings'])
            Holding.fromJson(Map<String, dynamic>.from(h)),
        ];
        trades = [
          for (final t in j['trades'])
            PortfolioTrade.fromJson(Map<String, dynamic>.from(t)),
        ];
        for (final h in holdings) {
          calculatePosition(h, trades);
        }
      }
    } catch (_) {
      error =
          'Archivio locale non leggibile. I dati esistenti non sono stati sovrascritti.';
    }
    loading = false;
    _notify();
    if (error == null) await refresh();
  }

  List<Position> get positions => [
    for (final h in holdings) calculatePosition(h, trades),
  ];
  MarketSeries? quote(Holding h) {
    final s = quotes[h.symbol];
    if (s == null ||
        s.currency != h.currency ||
        s.symbol.toUpperCase() != h.symbol.toUpperCase()) {
      return null;
    }
    if (h.snapshotDate != null &&
        s.points.last.time.isBefore(h.snapshotDate!)) {
      return null;
    }
    return s;
  }

  double? price(Holding h) => quote(h)?.latest ?? h.snapshotPrice;
  double? value(Position p) => p.quantity == 0
      ? 0
      : price(p.holding) == null
      ? null
      : money(p.quantity * price(p.holding)!);
  bool get complete =>
      positions.every((p) => p.holding.currency == 'EUR' && value(p) != null);
  double get totalValue => money(
    positions
        .where((p) => p.holding.currency == 'EUR')
        .fold(0.0, (v, p) => v + (value(p) ?? 0)),
  );
  double get netCapital => money(
    positions
        .where((p) => p.holding.currency == 'EUR')
        .fold(0.0, (v, p) => v + p.netCapital),
  );
  double get profit => money(totalValue - netCapital);
  double? get returnPercent =>
      complete && netCapital > 0 ? profit / netCapital * 100 : null;
  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    _notify();
    await Future.wait([
      for (final h in holdings)
        () async {
          try {
            quotes[h.symbol] = await market.fetchSeries(
              h.instrument,
              MarketPeriod.day,
            );
            if (quotes[h.symbol]!.currency != h.currency) {
              throw StateError('Valuta differente');
            }
            quoteErrors.remove(h.symbol);
          } catch (_) {
            quoteErrors[h.symbol] = 'Quotazione aggiornata non disponibile';
          }
          try {
            historySeries[h.symbol] = await market.fetchSeries(
              h.instrument,
              MarketPeriod.max,
            );
          } catch (_) {
            /* Keep valid previously fetched series. */
          }
        }(),
    ]);
    _historyCache.clear();
    refreshing = false;
    _notify();
  }

  final Map<String, List<PortfolioHistoryPoint>> _historyCache = {};

  /// La data più vecchia tra saldi iniziali e operazioni, se esiste.
  DateTime? get firstActivityDate {
    final dates = <DateTime>[
      for (final h in holdings)
        if (h.openingDate != null) h.openingDate!,
      for (final t in trades) t.date,
    ];
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  List<PortfolioHistoryPoint> historyFor(DateTime start, DateTime end) {
    final key =
        '${start.year}-${start.month}-${start.day}/${end.year}-${end.month}-${end.day}';
    return _historyCache.putIfAbsent(
      key,
      () => portfolioHistory(holdings, trades, historySeries, start, end),
    );
  }

  Future<void> _persist(List<Holding> h, List<PortfolioTrade> t) => store.write(
    _key,
    jsonEncode({
      'version': 1,
      'holdings': h.map((h) => h.toJson()).toList(),
      'trades': t.map((t) => t.toJson()).toList(),
    }),
  );
  Future<void> save({
    Holding? holding,
    PortfolioTrade? trade,
    String? deleteTrade,
  }) async {
    if (saving || error != null) {
      throw StateError('Archivio non disponibile o salvataggio in corso.');
    }
    final hs = [...holdings];
    if (holding != null) {
      if (holding.symbol.isEmpty ||
          holding.name.isEmpty ||
          holding.currency.length != 3 ||
          ![
            holding.openingQuantity,
            holding.openingCost,
          ].every((v) => v.isFinite && v >= 0) ||
          (holding.snapshotPrice != null &&
              (!holding.snapshotPrice!.isFinite ||
                  holding.snapshotPrice! <= 0))) {
        throw ArgumentError('Dati strumento non validi.');
      }
      final index = hs.indexWhere((h) => h.symbol == holding.symbol);
      if (index < 0) {
        hs.add(holding);
      } else {
        hs[index] = holding;
      }
    }
    final ts = trades
        .where((t) => t.id != deleteTrade && t.id != trade?.id)
        .toList();
    if (trade != null) {
      if (!hs.any((h) => h.symbol == trade.symbol)) {
        throw ArgumentError('Strumento non trovato.');
      }
      if (trade.date.isAfter(DateTime.now())) {
        throw ArgumentError('La data non può essere futura.');
      }
      ts.add(trade);
    }
    for (final h in hs) {
      calculatePosition(h, ts);
    }
    saving = true;
    _notify();
    try {
      await _persist(hs, ts);
      holdings = hs;
      trades = ts;
      _historyCache.clear();
    } finally {
      saving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
