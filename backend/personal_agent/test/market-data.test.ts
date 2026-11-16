import { describe, expect, it, vi } from "vitest";

import {
  fetchMarketSeries,
  MarketDataError,
  requireMarketPeriod,
  requireMarketSymbol,
} from "../src/markets/market-data";

describe("desktop market data", () => {
  it("normalizes symbols and validates periods", () => {
    expect(requireMarketSymbol(" btc-usd ")).toBe("BTC-USD");
    expect(requireMarketPeriod("1mo")).toBe("1mo");
    expect(() => requireMarketSymbol("bad symbol")).toThrow(MarketDataError);
    expect(() => requireMarketPeriod("2y")).toThrow(MarketDataError);
  });

  it("resolves Dogecoin aliases to the crypto price source", async () => {
    const fetcher = vi.fn(async (input: string | URL | Request) => {
      void input;
      return new Response(
        JSON.stringify({
          bars: [{ openTime: "2026-08-25T10:00:00Z", close: 0.2 }],
          mid: 0.2,
          timestamp: "2026-08-25T10:00:00Z",
        }),
      );
    });

    await fetchMarketSeries("DOGECOIN", "1d", fetcher);
    expect(fetcher.mock.calls[0]?.[0].toString()).toContain(
      "/coins/dogecoin/market_chart",
    );
  });

  it("loads supported crypto from CoinGecko instead of the general market feed", async () => {
    const fetcher = vi.fn(async (input: string | URL | Request) => {
      const url = new URL(input.toString());
      expect(url.hostname).toBe("api.coingecko.com");
      expect(url.pathname).toContain("/coins/dogecoin/market_chart");
      return new Response(JSON.stringify({ prices: [[1_787_652_000_000, 0.2]] }));
    });

    const result = await fetchMarketSeries("DOGE", "1d", fetcher);
    expect(result.exchange).toBe("CoinGecko");
    expect(result.points).toEqual([{ timestamp: 1_787_652_000, close: 0.2 }]);
  });

  it("normalizes live ticks and OHLC bars", async () => {
    const fetcher = vi.fn(async (input: string | URL | Request) => {
      const url = new URL(input.toString());
      if (url.pathname.endsWith("/ohlc")) {
        return new Response(
          JSON.stringify({
            symbol: "US500",
            interval: "1m",
            bars: [
              { openTime: "2026-08-25T10:01:00Z", close: 6415.5 },
              { openTime: "2026-08-25T10:00:00Z", close: 6401 },
            ],
          }),
        );
      }
      return new Response(
        JSON.stringify({
          symbol: "US500",
          description: "US SPX 500 Index",
          mid: 6418,
          timestamp: "2026-08-25T10:02:00Z",
          source: "MT5",
          marketState: "open",
        }),
      );
    });

    const result = await fetchMarketSeries("^GSPC", "1d", fetcher);

    expect(result.name).toBe("US SPX 500 Index");
    expect(result.previousClose).toBeNull();
    expect(result.points).toEqual([
      { timestamp: 1_787_652_000, close: 6401 },
      { timestamp: 1_787_652_060, close: 6415.5 },
      { timestamp: 1_787_652_120, close: 6418 },
    ]);
    expect(fetcher).toHaveBeenCalledTimes(2);
    expect(fetcher.mock.calls[0]?.[0].toString()).toContain("/US500/ohlc");
  });

  it("maps an empty provider result to symbol not found", async () => {
    const fetcher = vi.fn(
      async () =>
        new Response(JSON.stringify({ message: "not found" }), { status: 404 }),
    );

    await expect(fetchMarketSeries("NOPE", "1d", fetcher)).rejects.toMatchObject({
      status: 404,
      code: "symbol_not_found",
    });
  });
});
