import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/markets/domain/market_currency.dart';
import 'package:monitoraggio_personale_desktop/features/markets/domain/market_models.dart';

MarketSeries series(
  String currency,
  List<MarketPoint> points, {
  double? previousClose,
}) => MarketSeries(
  symbol: currency == 'USD' ? 'TEST-USD' : 'TEST-EUR',
  name: 'Test',
  currency: currency,
  exchange: 'TEST',
  previousClose: previousClose,
  points: points,
  updatedAt: points.last.time,
);
MarketPoint point(int day, double close) =>
    MarketPoint(time: DateTime.utc(2026, 10, day, 12), close: close);

void main() {
  test(
    'converts USD and EUR using each historical rate, preserving raw prices',
    () {
      final usd = series('USD', [
        point(5, 100),
        point(6, 200),
      ], previousClose: 80);
      final rates = series('USD', [point(4, 2), point(5, 2), point(6, 4)]);
      final eur = convertMarketCurrency(
        usd,
        rates,
        currency: 'EUR',
        inverse: true,
      );
      expect(eur.points.map((p) => p.close), [50, 50]);
      expect(eur.previousClose, 40);
      expect(eur.symbol, usd.symbol);
      expect(usd.points.last.close, 200);
      final back = convertMarketCurrency(
        eur,
        rates,
        currency: 'USD',
        inverse: false,
      );
      expect(back.points.map((p) => p.close), [100, 200]);
      expect(back.previousClose, 80);
    },
  );

  test('never substitutes a future or stale exchange rate', () {
    final usd = series('USD', [point(5, 100)]);
    for (final rate in [point(6, 2), point(1, 2)]) {
      // The stale observation is more than four days old.
      final actual = rate.time.day == 1
          ? MarketPoint(
              time: rate.time.subtract(const Duration(seconds: 1)),
              close: rate.close,
            )
          : rate;
      expect(
        () => convertMarketCurrency(
          usd,
          series('USD', [actual]),
          currency: 'EUR',
          inverse: true,
        ),
        throwsStateError,
      );
    }
  });
}
