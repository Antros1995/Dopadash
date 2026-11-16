const periodConfig = {
  "1d": { interval: "1m", limit: 600 },
  "5d": { interval: "30m", limit: 300 },
  "1mo": { interval: "4h", limit: 240 },
  "1y": { interval: "1d", limit: 370 },
  max: { interval: "1d", limit: 1000 },
} as const;

const symbolAliases: Record<string, string> = {
  "^GSPC": "US500",
  "^IXIC": "USTEC",
  "^NDX": "USTEC",
  "^DJI": "US30",
  "^STOXX50E": "DE30",
  "BTC-USD": "BTCUSD",
  "ETH-USD": "ETHUSD",
  DOGE: "DOGEUSD",
  "DOGE-USD": "DOGEUSD",
  DOGECOIN: "DOGEUSD",
  SOLANA: "SOLUSD",
  RIPPLE: "XRPUSD",
  CARDANO: "ADAUSD",
  AVALANCHE: "AVAXUSD",
  POLKADOT: "DOTUSD",
  CHAINLINK: "LINKUSD",
  LITECOIN: "LTCUSD",
  "BITCOIN-CASH": "BCHUSD",
  "SHIBA-INU": "SHIBUSD",
  PEPE: "PEPEUSD",
  UNISWAP: "UNIUSD",
  AAVE: "AAVEUSD",
  COSMOS: "ATOMUSD",
  "NEAR-PROTOCOL": "NEARUSD",
  "INTERNET-COMPUTER": "ICPUSD",
  STELLAR: "XLMUSD",
  HEDERA: "HBARUSD",
  CRONOS: "CROUSD",
  POLYGON: "POLUSD",
  ARBITRUM: "ARBUSD",
  OPTIMISM: "OPUSD",
  FILECOIN: "FILUSD",
  APTOS: "APTUSD",
  SUI: "SUIUSD",
  ALGORAND: "ALGOUSD",
  VECHAIN: "VETUSD",
  "THE-GRAPH": "GRTUSD",
  MAKER: "MKRUSD",
  RENDER: "RENDERUSD",
  FLOKI: "FLOKIUSD",
};

const cryptoCoinIds: Record<string, string> = {
  BTC: "bitcoin", "BTC-USD": "bitcoin", BITCOIN: "bitcoin",
  ETH: "ethereum", "ETH-USD": "ethereum", ETHEREUM: "ethereum",
  DOGE: "dogecoin", "DOGE-USD": "dogecoin", DOGECOIN: "dogecoin",
  SOL: "solana", "SOL-USD": "solana", SOLANA: "solana",
  XRP: "ripple", "XRP-USD": "ripple", RIPPLE: "ripple",
  ADA: "cardano", "ADA-USD": "cardano", CARDANO: "cardano",
  AVAX: "avalanche-2", "AVAX-USD": "avalanche-2", AVALANCHE: "avalanche-2",
  DOT: "polkadot", "DOT-USD": "polkadot", POLKADOT: "polkadot",
  LINK: "chainlink", "LINK-USD": "chainlink", CHAINLINK: "chainlink",
  LTC: "litecoin", "LTC-USD": "litecoin", LITECOIN: "litecoin",
  BCH: "bitcoin-cash", "BCH-USD": "bitcoin-cash", "BITCOIN-CASH": "bitcoin-cash",
  SHIB: "shiba-inu", "SHIB-USD": "shiba-inu", "SHIBA-INU": "shiba-inu",
  UNI: "uniswap", "UNI-USD": "uniswap", UNISWAP: "uniswap",
  AAVE: "aave", "AAVE-USD": "aave",
  ATOM: "cosmos", "ATOM-USD": "cosmos", COSMOS: "cosmos",
  XLM: "stellar", "XLM-USD": "stellar", STELLAR: "stellar",
  HBAR: "hedera-hashgraph", "HBAR-USD": "hedera-hashgraph", HEDERA: "hedera-hashgraph",
  POL: "polygon-ecosystem-token", "POL-USD": "polygon-ecosystem-token", POLYGON: "polygon-ecosystem-token",
  ARB: "arbitrum", "ARB-USD": "arbitrum", ARBITRUM: "arbitrum",
  OP: "optimism", "OP-USD": "optimism", OPTIMISM: "optimism",
  FIL: "filecoin", "FIL-USD": "filecoin", FILECOIN: "filecoin",
  APT: "aptos", "APT-USD": "aptos", APTOS: "aptos",
  SUI: "sui", "SUI-USD": "sui",
  ALGO: "algorand", "ALGO-USD": "algorand", ALGORAND: "algorand",
  VET: "vechain", "VET-USD": "vechain", VECHAIN: "vechain",
  GRT: "the-graph", "GRT-USD": "the-graph", "THE-GRAPH": "the-graph",
  MKR: "maker", "MKR-USD": "maker", MAKER: "maker",
  RENDER: "render-token", "RENDER-USD": "render-token",
  FLOKI: "floki", "FLOKI-USD": "floki",
  PEPE: "pepe", "PEPE-USD": "pepe",
};

type MarketPeriod = keyof typeof periodConfig;
type Fetcher = typeof fetch;

export class MarketDataError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "MarketDataError";
  }
}

export interface MarketPoint {
  timestamp: number;
  close: number;
}

export interface MarketSeries {
  symbol: string;
  name: string;
  currency: string;
  exchange: string;
  previousClose: number | null;
  points: MarketPoint[];
  updatedAt: string;
}

export function requireMarketSymbol(value: string | null): string {
  const symbol = value?.trim().toUpperCase() ?? "";
  if (!/^[A-Z0-9^=._-]{1,24}$/u.test(symbol)) {
    throw new MarketDataError(400, "invalid_symbol", "Invalid market symbol");
  }
  return symbol;
}

export function requireMarketPeriod(value: string | null): MarketPeriod {
  const period = value?.trim() ?? "1d";
  if (!(period in periodConfig)) {
    throw new MarketDataError(400, "invalid_period", "Invalid market period");
  }
  return period as MarketPeriod;
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function providerSymbol(symbol: string): string {
  return symbolAliases[symbol] ?? symbol.replace(/-/gu, "");
}

async function fetchCryptoSeries(
  symbol: string,
  period: MarketPeriod,
  fetcher: Fetcher,
): Promise<MarketSeries | null> {
  const coinId = cryptoCoinIds[symbol];
  if (!coinId) return null;
  const days: Record<MarketPeriod, string> = {
    "1d": "1", "5d": "5", "1mo": "30", "1y": "365", max: "max",
  };
  const url = new URL(`https://api.coingecko.com/api/v3/coins/${coinId}/market_chart`);
  url.searchParams.set("vs_currency", "usd");
  url.searchParams.set("days", days[period]);
  const { response, body } = await providerJson(url, fetcher);
  const prices = record(body)?.prices;
  if (!response.ok || !Array.isArray(prices)) return null;
  const points: MarketPoint[] = [];
  for (const price of prices) {
    if (!Array.isArray(price) || price.length < 2) continue;
    const timestamp = finiteNumber(price[0]);
    const close = finiteNumber(price[1]);
    if (timestamp !== null && close !== null) {
      points.push({ timestamp: Math.floor(timestamp / 1000), close });
    }
  }
  if (points.length === 0) return null;
  return {
    symbol,
    name: coinId.replace(/-/gu, " "),
    currency: "USD",
    exchange: "CoinGecko",
    previousClose: null,
    points,
    updatedAt: new Date().toISOString(),
  };
}

async function providerJson(
  url: URL,
  fetcher: Fetcher,
): Promise<{ response: Response; body: unknown }> {
  let response: Response;
  try {
    response = await fetcher(url, {
      headers: { accept: "application/json" },
      cf: { cacheTtl: 0, cacheEverything: false },
    });
  } catch {
    throw new MarketDataError(
      502,
      "market_data_unavailable",
      "Live market provider unavailable",
    );
  }
  let body: unknown = null;
  try {
    body = await response.json();
  } catch {
    // The response status below remains the authoritative failure signal.
  }
  return { response, body };
}

export async function fetchMarketSeries(
  symbol: string,
  period: MarketPeriod,
  fetcher: Fetcher = fetch,
): Promise<MarketSeries> {
  const crypto = await fetchCryptoSeries(symbol, period, fetcher);
  if (crypto) return crypto;
  const config = periodConfig[period];
  const feedSymbol = providerSymbol(symbol);
  const barsUrl = new URL(
    `https://biquote.io/api/${encodeURIComponent(feedSymbol)}/ohlc`,
  );
  barsUrl.searchParams.set("interval", config.interval);
  barsUrl.searchParams.set("limit", String(config.limit));
  const tickUrl = new URL(
    `https://biquote.io/api/${encodeURIComponent(feedSymbol)}`,
  );
  tickUrl.searchParams.set("allowStale", "true");

  const [barsResult, tickResult] = await Promise.all([
    providerJson(barsUrl, fetcher),
    providerJson(tickUrl, fetcher),
  ]);
  if (barsResult.response.status === 404 || tickResult.response.status === 404) {
    throw new MarketDataError(404, "symbol_not_found", "Symbol not found");
  }
  if (!barsResult.response.ok || !tickResult.response.ok) {
    throw new MarketDataError(
      502,
      "market_data_unavailable",
      `Live market provider rejected the request (${barsResult.response.status}/${tickResult.response.status})`,
    );
  }

  const barsBody = record(barsResult.body);
  const tick = record(tickResult.body);
  const bars = barsBody?.bars;
  if (!Array.isArray(bars) || tick === null) {
    throw new MarketDataError(
      502,
      "invalid_market_response",
      "Live market series is missing",
    );
  }
  const points: MarketPoint[] = [];
  for (const value of bars) {
    const bar = record(value);
    const close = finiteNumber(bar?.close);
    const openTime =
      typeof bar?.openTime === "string" ? Date.parse(bar.openTime) : NaN;
    if (close !== null && Number.isFinite(openTime)) {
      points.push({ timestamp: Math.floor(openTime / 1000), close });
    }
  }
  points.sort((left, right) => left.timestamp - right.timestamp);

  const latest = finiteNumber(tick.mid);
  const tickTimestamp =
    typeof tick.timestamp === "string" ? Date.parse(tick.timestamp) : NaN;
  if (latest !== null && Number.isFinite(tickTimestamp)) {
    const timestamp = Math.floor(tickTimestamp / 1000);
    const lastPoint = points.at(-1);
    if (lastPoint?.timestamp === timestamp) {
      lastPoint.close = latest;
    } else if (lastPoint === undefined || timestamp > lastPoint.timestamp) {
      points.push({ timestamp, close: latest });
    }
  }
  if (points.length === 0) {
    throw new MarketDataError(404, "symbol_not_found", "No market prices found");
  }

  const description =
    typeof tick.description === "string" && tick.description.trim()
      ? tick.description.trim()
      : symbol;
  const marketState =
    typeof tick.marketState === "string" ? tick.marketState.toUpperCase() : "";
  const source = typeof tick.source === "string" ? tick.source : "LIVE";
  const updatedAt =
    typeof tick.timestamp === "string" &&
    Number.isFinite(Date.parse(tick.timestamp))
      ? new Date(tick.timestamp).toISOString()
      : new Date().toISOString();
  return {
    symbol,
    name: description,
    currency: "USD",
    exchange: marketState ? `${source} · ${marketState}` : source,
    previousClose: null,
    points,
    updatedAt,
  };
}
