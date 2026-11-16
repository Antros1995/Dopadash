import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/markets/application/market_controller.dart';
import 'package:monitoraggio_personale_desktop/features/markets/data/market_repository.dart';
import 'package:monitoraggio_personale_desktop/features/markets/domain/market_models.dart';
import 'package:monitoraggio_personale_desktop/features/markets/presentation/markets_page.dart';
import 'package:monitoraggio_personale_desktop/features/markets/presentation/finance_widgets.dart';

void main() {
  testWidgets('switches Borsa prices and chart from default EUR to USD', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1354, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CurrencyRepository();
    final controller = MarketController(repository: repository);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(body: MarketsPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.currency, 'EUR');
    expect(controller.seriesFor('^GSPC')!.latest, 50);
    expect(
      tester.widget<FinanceChart>(find.byType(FinanceChart)).currency,
      'EUR',
    );
    expect(
      tester.widget<FinanceChart>(find.byType(FinanceChart)).points.last.value,
      50,
    );

    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();
    expect(controller.currency, 'USD');
    expect(controller.seriesFor('^GSPC')!.latest, 100);
    expect(
      tester.widget<FinanceChart>(find.byType(FinanceChart)).currency,
      'USD',
    );
    expect(
      tester.widget<FinanceChart>(find.byType(FinanceChart)).points.last.value,
      100,
    );

    await tester.tap(find.text('EUR'));
    await tester.pumpAndSettle();
    expect(controller.seriesFor('^GSPC')!.latest, 50);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test('normalizes Dogecoin names to its USD ticker', () {
    expect(normalizeMarketSymbol('Dogecoin'), 'DOGE-USD');
    expect(normalizeMarketSymbol('doge'), 'DOGE-USD');
    expect(normalizeMarketSymbol('Solana'), 'SOL-USD');
    expect(normalizeMarketSymbol('Chainlink'), 'LINK-USD');
  });

  testWidgets('renders market overview and switches the main chart period', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1354, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _MarketRepository();
    final controller = MarketController(repository: repository);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(body: MarketsPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Borsa'), findsOneWidget);
    expect(find.text('S&P 500'), findsWidgets);
    expect(find.text('Nasdaq Composite'), findsWidgets);
    expect(find.text('Andamento mercati'), findsOneWidget);

    // Sopra il grafico ora ci sono le mappe: il filtro va portato in vista.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '1Y'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '1Y'));
    await tester.pumpAndSettle();

    expect(repository.requests, contains(const ('^GSPC', MarketPeriod.year)));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Tutto'));
    await tester.pumpAndSettle();
    expect(repository.requests, contains(const ('^GSPC', MarketPeriod.max)));
    expect(find.byType(FinanceChart), findsOneWidget);
    expect(find.textContaining('25/08/2026'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test('moves and persists the watchlist order', () async {
    final repository = _MarketRepository();
    final controller = MarketController(repository: repository);
    addTearDown(controller.dispose);

    await controller.load();
    await controller.move('^IXIC', -1);

    expect(controller.instruments.first.symbol, '^IXIC');
    expect(repository.saved.first.symbol, '^IXIC');
  });
}

class _MarketRepository implements MarketRepository {
  final requests = <(String, MarketPeriod)>[];
  List<MarketInstrument> saved = const [];

  @override
  Future<List<MarketInstrument>> loadWatchlist() async => const [
    MarketInstrument(symbol: '^GSPC', name: 'S&P 500'),
    MarketInstrument(symbol: '^IXIC', name: 'Nasdaq Composite'),
  ];

  @override
  Future<MarketSeries> fetchSeries(
    MarketInstrument instrument,
    MarketPeriod period,
  ) async {
    requests.add((instrument.symbol, period));
    final fx = instrument.symbol == 'EURUSD=X';
    return MarketSeries(
      symbol: instrument.symbol,
      name: instrument.name,
      currency: 'USD',
      exchange: 'TEST',
      previousClose: fx ? 2 : 100,
      points: [
        MarketPoint(time: DateTime(2026, 8, 25, 9), close: fx ? 2 : 100),
        MarketPoint(time: DateTime(2026, 8, 25, 10), close: fx ? 2 : 102),
        MarketPoint(time: DateTime(2026, 8, 25, 11), close: fx ? 2 : 101),
      ],
      updatedAt: DateTime(2026, 8, 25, 11),
    );
  }

  @override
  Future<void> saveWatchlist(List<MarketInstrument> instruments) async {
    saved = [...instruments];
  }

  @override
  void dispose() {}
}

class _CurrencyRepository extends _MarketRepository {
  @override
  Future<MarketSeries> fetchSeries(
    MarketInstrument instrument,
    MarketPeriod period,
  ) async {
    requests.add((instrument.symbol, period));
    final fx = instrument.symbol == 'EURUSD=X';
    final time = DateTime.now().subtract(const Duration(hours: 2));
    return MarketSeries(
      symbol: instrument.symbol,
      name: instrument.name,
      currency: 'USD',
      exchange: 'TEST',
      previousClose: fx ? 2 : 90,
      points: [
        MarketPoint(
          time: time.subtract(const Duration(days: 1)),
          close: fx ? 2 : 90,
        ),
        MarketPoint(time: time, close: fx ? 2 : 100),
      ],
      updatedAt: time,
    );
  }
}
