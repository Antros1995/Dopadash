import { describe, expect, it, vi } from 'vitest';
import { fetchProductionMarketSeries } from '../src/markets/production-market-data';
const fixture = (symbol: string, currency = 'EUR', granularity = '1d') => ({ chart: { result: [{
  meta: { symbol, currency, dataGranularity: granularity, fullExchangeName: 'Milan', longName: symbol, chartPreviousClose: 99 },
  timestamp: [1727650800, 1727737200, 1727823600],
  indicators: { quote: [{ close: [100, null, 102] }] },
}] } });
describe('production portfolio prices', () => {
  it.each(['SMEA.MI', 'IUSE.MI', 'SWDA.MI', 'XRP-EUR'])('preserves %s and real EUR daily history without max downsampling', async (symbol) => {
    const fetcher = vi.fn(async (input: string | URL | Request) => {
      const url = new URL(input.toString());
      expect(url.hostname).toBe('query1.finance.yahoo.com');
      expect(decodeURIComponent(url.pathname)).toContain(symbol);
      expect(url.searchParams.get('interval')).toBe('1d');
      expect(url.searchParams.get('period1')).toBe('0');
      expect(url.searchParams.has('range')).toBe(false);
      return Response.json(fixture(symbol));
    });
    const result = await fetchProductionMarketSeries(symbol, 'max', fetcher);
    expect(result.symbol).toBe(symbol); expect(result.currency).toBe('EUR');
    expect(result.points).toEqual([{ timestamp: 1727650800, close: 100 }, { timestamp: 1727823600, close: 102 }]);
    expect(result.updatedAt).toBe(new Date(1727823600000).toISOString());
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('rejects a different instrument, currency, or downsampled history', async () => {
    for (const data of [fixture('OTHER.MI'), fixture('SWDA.MI', 'USD'), fixture('SWDA.MI', 'EUR', '3mo')]) {
      await expect(fetchProductionMarketSeries('SWDA.MI', 'max', async () => Response.json(data))).rejects.toMatchObject({ code: 'invalid_market_response' });
    }
  });
  it('does not replace source failures with a different asset or invented history', async () => {
    const fetcher = vi.fn(async () => new Response('', { status: 429 }));
    await expect(fetchProductionMarketSeries('XRP-EUR', 'max', fetcher)).rejects.toMatchObject({ code: 'market_data_unavailable' });
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
});
