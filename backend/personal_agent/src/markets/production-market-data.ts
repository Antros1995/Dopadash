import { MarketDataError, requireMarketPeriod, requireMarketSymbol, type MarketSeries } from './market-data';

type Period = ReturnType<typeof requireMarketPeriod>;
const intervals: Record<Period, string> = { '1d': '5m', '5d': '30m', '1mo': '1d', '1y': '1d', max: '1d' };
const cache = new Map<string, { expires: number; series: MarketSeries }>();
const pending = new Map<string, Promise<MarketSeries>>();
const object = (v: unknown): Record<string, unknown> => v && typeof v === 'object' ? v as Record<string, unknown> : {};
const positive = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v > 0;

// Same instrument/currency and daily history as the local adapter, served by
// the existing authenticated /api/desktop/markets route. No Node server needed.
export async function fetchProductionMarketSeries(symbol: string, period: Period, fetcher: typeof fetch = fetch): Promise<MarketSeries> {
  symbol = requireMarketSymbol(symbol);
  period = requireMarketPeriod(period);
  const key = `${symbol}:${period}`;
  const shared = fetcher === fetch;
  if (shared) {
    const found = cache.get(key);
    if (found && found.expires > Date.now()) return found.series;
    const running = pending.get(key);
    if (running) return running;
  }
  const request = fetchYahoo(symbol, period, fetcher);
  if (shared) pending.set(key, request);
  try {
    const series = await request;
    if (shared) {
      if (cache.size >= 64) cache.delete(cache.keys().next().value!);
      cache.set(key, { series, expires: Date.now() + (period === '1d' ? 25000 : 600000) });
    }
    return series;
  } finally { if (shared) pending.delete(key); }
}

async function fetchYahoo(symbol: string, period: Period, fetcher: typeof fetch): Promise<MarketSeries> {
  const aliases: Record<string, string> = { DE30: '^GDAXI', BTC: 'BTC-USD', BITCOIN: 'BTC-USD', ETH: 'ETH-USD', ETHEREUM: 'ETH-USD', DOGE: 'DOGE-USD', DOGECOIN: 'DOGE-USD', XRP: 'XRP-USD', RIPPLE: 'XRP-USD' };
  const ticker = aliases[symbol] ?? symbol;
  const url = new URL(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}`);
  url.searchParams.set('interval', intervals[period]);
  if (period === 'max') {
    // range=max silently down-samples long histories. Explicit dates keep 1d.
    url.searchParams.set('period1', '0');
    url.searchParams.set('period2', String(Math.floor(Date.now() / 1000)));
  } else { url.searchParams.set('range', period); }
  let body: unknown;
  try {
    const response = await fetcher(url, { headers: { accept: 'application/json', 'User-Agent': 'LocalPortfolio/1.0' }, signal: AbortSignal.timeout(14000) });
    if (!response.ok) throw new MarketDataError(response.status === 404 ? 404 : 502, response.status === 404 ? 'symbol_not_found' : 'market_data_unavailable', 'Price source unavailable');
    body = await response.json();
  } catch (error) {
    if (error instanceof MarketDataError) throw error;
    throw new MarketDataError(502, 'market_data_unavailable', 'Price source unavailable');
  }
  const chart = object(object(body).chart);
  const result = Array.isArray(chart.result) ? object(chart.result[0]) : {};
  const meta = object(result.meta);
  const currency = typeof meta.currency === 'string' ? meta.currency.toUpperCase() : '';
  const expectedCurrency = ticker.endsWith('.MI') || ticker.endsWith('-EUR') ? 'EUR' : null;
  if (chart.error || typeof meta.symbol !== 'string' || meta.symbol.toUpperCase() !== ticker || !/^[A-Z]{3}$/.test(currency) || (expectedCurrency && currency !== expectedCurrency)) {
    throw new MarketDataError(502, 'invalid_market_response', 'Instrument or currency mismatch');
  }
  if (period === 'max' && meta.dataGranularity !== '1d') throw new MarketDataError(502, 'invalid_market_response', 'Daily history unavailable');
  const timestamps = Array.isArray(result.timestamp) ? result.timestamp : [];
  const quotes = object(result.indicators).quote;
  const closes = Array.isArray(quotes) ? object(quotes[0]).close : [];
  const points = timestamps.flatMap((time: unknown, i: number) => {
    const close: unknown = Array.isArray(closes) ? closes[i] : null;
    return positive(time) && positive(close) ? [{ timestamp: time, close }] : [];
  }).sort((a, b) => a.timestamp - b.timestamp);
  if (!points.length) throw new MarketDataError(404, 'symbol_not_found', 'No valid prices');
  const previous = meta.chartPreviousClose ?? meta.previousClose;
  return { symbol, name: String(meta.longName ?? meta.shortName ?? symbol), currency,
    exchange: `Yahoo Finance · ${String(meta.fullExchangeName ?? meta.exchangeName ?? '')}`,
    previousClose: positive(previous) ? previous : null, points,
    updatedAt: new Date(points[points.length - 1]!.timestamp * 1000).toISOString() };
}
