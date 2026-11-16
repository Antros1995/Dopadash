enum MarketPeriod {
  day('1d', '1G'),
  week('5d', '1S'),
  month('1mo', '1M'),
  year('1y', '1A'),
  max('max', 'MAX');

  const MarketPeriod(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// Converts common crypto names into the USD ticker accepted by the market API.
/// Users may still enter any normal ticker unchanged.
String normalizeMarketSymbol(String value) {
  const aliases = <String, String>{
    'BITCOIN': 'BTC-USD',
    'BTC': 'BTC-USD',
    'ETHEREUM': 'ETH-USD',
    'ETH': 'ETH-USD',
    'DOGECOIN': 'DOGE-USD',
    'DOGE': 'DOGE-USD',
    'SOLANA': 'SOL-USD',
    'RIPPLE': 'XRP-USD',
    'CARDANO': 'ADA-USD',
    'AVALANCHE': 'AVAX-USD',
    'POLKADOT': 'DOT-USD',
    'CHAINLINK': 'LINK-USD',
    'LITECOIN': 'LTC-USD',
    'BITCOIN CASH': 'BCH-USD',
    'SHIBA INU': 'SHIB-USD',
    'PEPE': 'PEPE-USD',
    'UNISWAP': 'UNI-USD',
    'AAVE': 'AAVE-USD',
    'COSMOS': 'ATOM-USD',
    'NEAR PROTOCOL': 'NEAR-USD',
    'INTERNET COMPUTER': 'ICP-USD',
    'STELLAR': 'XLM-USD',
    'HEDERA': 'HBAR-USD',
    'CRONOS': 'CRO-USD',
    'POLYGON': 'POL-USD',
    'ARBITRUM': 'ARB-USD',
    'OPTIMISM': 'OP-USD',
    'FILECOIN': 'FIL-USD',
    'APTOS': 'APT-USD',
    'SUI': 'SUI-USD',
    'ALGORAND': 'ALGO-USD',
    'VECHAIN': 'VET-USD',
    'THE GRAPH': 'GRT-USD',
    'MAKER': 'MKR-USD',
    'RENDER': 'RENDER-USD',
    'FLOKI': 'FLOKI-USD',
  };
  final normalized = value.trim().toUpperCase();
  return aliases[normalized] ?? normalized;
}

class MarketInstrument {
  const MarketInstrument({
    required this.symbol,
    required this.name,
    this.assetCategory,
  });

  final String symbol;
  final String name;
  final String? assetCategory;
  String get category =>
      assetCategory ??
      (symbol.startsWith('^') || symbol == 'DE30'
          ? 'Indici'
          : symbol.contains('-')
          ? 'Crypto'
          : symbol.endsWith('.MI')
          ? 'ETF'
          : 'Azioni');

  Map<String, Object?> toJson() => {
    'symbol': symbol,
    'name': name,
    'category': category,
  };

  static MarketInstrument? fromJson(Object? value) {
    if (value is! Map) return null;
    final symbol = value['symbol'];
    final name = value['name'];
    if (symbol is! String || name is! String) return null;
    final normalizedSymbol = symbol.trim().toUpperCase();
    final normalizedName = name.trim();
    if (normalizedSymbol.isEmpty || normalizedName.isEmpty) return null;
    return MarketInstrument(
      symbol: normalizedSymbol,
      name: normalizedName,
      assetCategory: value['category'] as String?,
    );
  }
}

class MarketPoint {
  const MarketPoint({required this.time, required this.close});

  final DateTime time;
  final double close;
}

class MarketSeries {
  const MarketSeries({
    required this.symbol,
    required this.name,
    required this.currency,
    required this.exchange,
    required this.previousClose,
    required this.points,
    required this.updatedAt,
  });

  final String symbol;
  final String name;
  final String currency;
  final String exchange;
  final double? previousClose;
  final List<MarketPoint> points;
  final DateTime updatedAt;

  double get latest => points.last.close;

  double baselineFor(MarketPeriod period) {
    if (period == MarketPeriod.day && previousClose != null) {
      return previousClose!;
    }
    return points.first.close;
  }

  double changeFor(MarketPeriod period) => latest - baselineFor(period);

  double changePercentFor(MarketPeriod period) {
    final baseline = baselineFor(period);
    return baseline == 0 ? 0 : changeFor(period) / baseline * 100;
  }
}

const defaultMarketInstruments = <MarketInstrument>[
  MarketInstrument(symbol: '^GSPC', name: 'S&P 500'),
  MarketInstrument(symbol: '^IXIC', name: 'Nasdaq Composite'),
  MarketInstrument(symbol: '^DJI', name: 'Dow Jones'),
  MarketInstrument(symbol: 'DE30', name: 'DAX'),
  MarketInstrument(symbol: 'BTC-USD', name: 'Bitcoin'),
  MarketInstrument(symbol: 'ETH-USD', name: 'Ethereum'),
];
