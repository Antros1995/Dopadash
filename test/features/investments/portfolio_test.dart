import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/core/storage/key_value_store.dart';
import 'package:monitoraggio_personale_desktop/features/investments/portfolio.dart';
import 'package:monitoraggio_personale_desktop/features/markets/data/local_market_repository.dart';
import 'package:monitoraggio_personale_desktop/features/markets/data/market_repository.dart';
import 'package:monitoraggio_personale_desktop/features/markets/domain/market_models.dart';

class MemoryStore implements KeyValueStore {
  final data = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('disk');
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async => data.remove(key);
}

class NoPrices implements MarketRepository {
  int calls = 0, writes = 0;
  bool available = false;
  @override
  Future<List<MarketInstrument>> loadWatchlist() async =>
      defaultMarketInstruments;
  @override
  Future<void> saveWatchlist(List<MarketInstrument> i) async {
    writes++;
  }

  @override
  Future<MarketSeries> fetchSeries(MarketInstrument i, MarketPeriod p) async {
    calls++;
    await Future<void>.delayed(Duration.zero);
    if (!available) throw const MarketFailure(MarketFailureKind.unavailable);
    return MarketSeries(
      symbol: i.symbol,
      name: i.name,
      currency: 'EUR',
      exchange: 'TEST',
      previousClose: 10,
      points: [MarketPoint(time: DateTime(2026, 9, 29), close: 20)],
      updatedAt: DateTime(2026, 9, 29),
    );
  }

  @override
  void dispose() {}
}

PortfolioTrade trade(
  String id,
  bool buy,
  double q,
  double p, {
  double fees = 0,
  int day = 2,
}) => PortfolioTrade(
  id: id,
  symbol: 'TEST',
  date: DateTime(2025, 1, day),
  buy: buy,
  quantity: q,
  price: p,
  fees: fees,
  currency: 'EUR',
);
final holding = Holding(
  symbol: 'TEST',
  name: 'Test',
  kind: AssetKind.etf,
  openingQuantity: 10,
  openingCost: 100,
  openingDate: DateTime(2025, 1, 1),
);
void main() {
  test('weighted cost, fees, partial sale and realized result reconcile', () {
    final p = calculatePosition(holding, [
      trade('1', true, 10, 20, fees: 2),
      trade('2', false, 5, 30, fees: 1, day: 3),
    ]);
    expect(p.quantity, 15);
    expect(p.cost, 226.50);
    expect(p.averageCost, 15.10);
    expect(p.netCapital, 153);
    expect(p.realized, 73.50);
    expect(450 - p.cost + p.realized, 450 - p.netCapital);
  });
  test(
    'overselling is rejected at operation date and nonfinite inputs rejected',
    () {
      expect(
        () => calculatePosition(holding, [
          trade('1', false, 11, 20),
          trade('2', true, 10, 20, day: 3),
        ]),
        throwsArgumentError,
      );
      expect(
        () => calculatePosition(holding, [trade('1', true, double.nan, 20)]),
        throwsArgumentError,
      );
    },
  );
  test('sale of all units resets cost and preserves realized outcome', () {
    final p = calculatePosition(holding, [trade('1', false, 10, 15, fees: 1)]);
    expect(p.quantity, 0);
    expect(p.cost, 0);
    expect(p.averageCost, 0);
    expect(p.realized, 49);
    expect(p.netCapital, -49);
  });
  test(
    'history uses quantities held on each day and separates new capital',
    () {
      final s = MarketSeries(
        symbol: 'TEST',
        name: 'Test',
        currency: 'EUR',
        exchange: 'TEST',
        previousClose: 10,
        points: [
          for (var day = 1; day <= 3; day++)
            MarketPoint(time: DateTime(2025, 1, day, 17), close: 20),
        ],
        updatedAt: DateTime(2025, 1, 3),
      );
      final result = portfolioHistory(
        [holding],
        [trade('1', true, 10, 20)],
        {'TEST': s},
        DateTime(2024, 12, 31),
        DateTime(2025, 1, 3),
      );
      expect(result.map((p) => p.value), [200, 400, 400]);
      expect(result.map((p) => p.capital), [100, 300, 300]);
      expect(result.map((p) => p.value - p.capital), [100, 100, 100]);
      expect(
        portfolioHistory(
          [holding],
          [],
          {},
          DateTime(2025, 1, 1),
          DateTime(2025, 1, 3),
        ),
        isEmpty,
      );
    },
  );
  test('unknown opening date cannot produce invented history', () {
    const h = Holding(
      symbol: 'TEST',
      name: 'Test',
      kind: AssetKind.etf,
      openingQuantity: 10,
      openingCost: 100,
    );
    expect(
      portfolioHistory([h], [], {}, DateTime(2025), DateTime(2026)),
      isEmpty,
    );
  });
  test('a new portfolio starts empty and is persisted', () async {
    final store = MemoryStore();
    final market = LocalMarketRepository(NoPrices(), store, 'a');
    final c = PortfolioController(store: store, market: market, scope: 'a');
    addTearDown(c.dispose);
    await c.load();
    expect(c.holdings, isEmpty);
    expect(c.totalValue, 0);
    final restored = PortfolioController(
      store: store,
      market: market,
      scope: 'a',
    );
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.holdings, isEmpty);
  });
  test(
    'persisted CRUD is atomic and deletion cannot invalidate later sale',
    () async {
      final store = MemoryStore(), source = NoPrices();
      final c = PortfolioController(
        store: store,
        market: LocalMarketRepository(source, store, 'a'),
        scope: 'a',
      );
      addTearDown(c.dispose);
      await c.load();
      await c.save(
        holding: const Holding(
          symbol: 'TEST',
          name: 'Test',
          kind: AssetKind.stock,
        ),
        trade: trade('1', true, 10, 10),
      );
      await c.save(trade: trade('2', false, 8, 20, day: 3));
      await expectLater(c.save(deleteTrade: '1'), throwsArgumentError);
      expect(c.trades.length, 2);
      store.fail = true;
      await expectLater(c.save(deleteTrade: '2'), throwsStateError);
      expect(c.trades.length, 2);
      store.fail = false;
      await c.save(deleteTrade: '2');
      await c.save(trade: trade('1', true, 4, 12));
      expect(c.positions.last.quantity, 4);
      expect(c.positions.last.cost, 48);
    },
  );
  test(
    'shared market cache deduplicates and watchlist never writes remotely',
    () async {
      final store = MemoryStore(), source = NoPrices()..available = true;
      final market = LocalMarketRepository(source, store, 'a');
      const i = MarketInstrument(symbol: 'TEST', name: 'Test');
      await Future.wait([
        market.fetchSeries(i, MarketPeriod.day),
        market.fetchSeries(i, MarketPeriod.day),
      ]);
      await market.fetchSeries(i, MarketPeriod.day);
      expect(source.calls, 1);
      await market.saveWatchlist([i]);
      expect(source.writes, 0);
      expect((await market.loadWatchlist()).single.symbol, 'TEST');
      await market.saveWatchlist([]);
      expect(await market.loadWatchlist(), isEmpty);
      final other = LocalMarketRepository(source, store, 'b');
      expect(await other.loadWatchlist(), isNotEmpty);
    },
  );
}
