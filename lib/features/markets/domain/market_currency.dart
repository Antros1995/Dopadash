import 'market_models.dart';

/// Uses the last real exchange-rate observation at or before each price.
/// Weekend prices may use Friday's rate; missing coverage is never fabricated.
MarketSeries convertMarketCurrency(
  MarketSeries source,
  MarketSeries rates, {
  required String currency,
  required bool inverse,
}) {
  if (source.currency == currency) return source;
  final points = <MarketPoint>[];
  var index = -1;
  double? rateAt(DateTime time) {
    while (index + 1 < rates.points.length &&
        !rates.points[index + 1].time.isAfter(time)) {
      index++;
    }
    if (index < 0) return null;
    final rate = rates.points[index];
    if (!rate.close.isFinite ||
        rate.close <= 0 ||
        time.difference(rate.time) > const Duration(days: 4)) {
      return null;
    }
    return inverse ? 1 / rate.close : rate.close;
  }

  double? previousClose;
  if (source.points.isNotEmpty && source.previousClose != null) {
    final first = source.points.first.time.toUtc();
    final rate = rateAt(
      DateTime.utc(
        first.year,
        first.month,
        first.day,
      ).subtract(const Duration(microseconds: 1)),
    );
    if (rate != null) previousClose = source.previousClose! * rate;
  }
  for (final point in source.points) {
    final rate = rateAt(point.time);
    if (rate != null) {
      points.add(MarketPoint(time: point.time, close: point.close * rate));
    }
  }
  if (points.isEmpty || points.last.time != source.points.last.time) {
    throw StateError('Cambio reale non disponibile per questa quotazione');
  }
  return MarketSeries(
    symbol: source.symbol,
    name: source.name,
    currency: currency,
    exchange: '${source.exchange} · cambio ${rates.symbol}',
    previousClose: previousClose,
    points: points,
    updatedAt: source.updatedAt,
  );
}
