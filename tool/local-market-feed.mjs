// Read-only local adapter. No account, key, remote configuration, or deployment.
const periods = { '1d': ['1d', '5m'], '5d': ['5d', '30m'], '1mo': ['1mo', '1d'], '1y': ['1y', '1d'], max: ['max', '1d'] };
const cache = new Map();
const pending = new Map();
export async function marketSeries(symbol, period) {
  if (!/^[A-Z0-9^=._-]{1,24}$/.test(symbol) || !periods[period]) throw new Error('Invalid symbol or period');
  const key = `${symbol}:${period}`;
  const cached = cache.get(key);
  if (cached && Date.now() - cached.time < (period === '1d' ? 25000 : 600000)) return cached.value;
  if (pending.has(key)) return pending.get(key);
  const request = (async () => {
    const [range, interval] = periods[period];
    // Preserve the market identity: DE30 was the existing DAX alias.
    const ticker = symbol === 'DE30' ? '^GDAXI' : symbol;
    const url = new URL(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}`);
    if (period === 'max') {
      url.searchParams.set('period1', '0');
      url.searchParams.set('period2', String(Math.floor(Date.now() / 1000)));
    } else { url.searchParams.set('range', range); }
    url.searchParams.set('interval', interval);
    const response = await fetch(url, { signal: AbortSignal.timeout(15000), headers: { 'User-Agent': 'LocalPortfolio/1.0' } });
    if (!response.ok) throw new Error(`Price source unavailable (${response.status})`);
    const body = await response.json();
    const series = body.chart?.result?.[0];
    if (!series || body.chart.error || series.meta?.symbol?.toUpperCase() !== ticker.toUpperCase()) throw new Error('Instrument not found');
    const quotes = series.indicators?.quote?.[0]?.close ?? [];
    // Use unadjusted closes: holdings quantity(t) is tracked independently.
    const points = (series.timestamp ?? []).flatMap((timestamp, i) => Number.isFinite(timestamp) && Number.isFinite(quotes[i]) && quotes[i] > 0 ? [{ timestamp, close: quotes[i] }] : []);
    if (!points.length || !series.meta.currency) throw new Error('No valid prices');
    points.sort((a, b) => a.timestamp - b.timestamp);
    const value = { symbol, name: series.meta.longName ?? series.meta.shortName ?? symbol, currency: series.meta.currency,
      exchange: `Yahoo Finance · ${series.meta.fullExchangeName ?? series.meta.exchangeName ?? ''}`,
      previousClose: series.meta.chartPreviousClose ?? series.meta.previousClose ?? null,
      points, updatedAt: new Date(points.at(-1).timestamp * 1000).toISOString() };
    cache.set(key, { time: Date.now(), value });
    return value;
  })();
  pending.set(key, request);
  try { return await request; } finally { pending.delete(key); }
}
