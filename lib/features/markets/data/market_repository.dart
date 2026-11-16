import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import '../../../core/sync/authorized_agent_request.dart';

import '../domain/market_models.dart';

enum MarketFailureKind {
  sessionExpired,
  notAllowed,
  symbolNotFound,
  unavailable,
  invalidResponse,
}

class MarketFailure implements Exception {
  const MarketFailure(this.kind);

  final MarketFailureKind kind;
}

abstract interface class MarketRepository {
  Future<List<MarketInstrument>> loadWatchlist();

  Future<void> saveWatchlist(List<MarketInstrument> instruments);

  Future<MarketSeries> fetchSeries(
    MarketInstrument instrument,
    MarketPeriod period,
  );

  void dispose();
}

class PersonalAgentMarketRepository implements MarketRepository {
  PersonalAgentMarketRepository({
    required this.supabase,
    required this.apiBaseUrl,
    http.Client? httpClient,
    this.accessTokenProvider,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  static const _metadataKey = 'market_dashboard';

  final SupabaseClient supabase;
  final Uri? apiBaseUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final String? Function()? accessTokenProvider;

  @override
  Future<List<MarketInstrument>> loadWatchlist() async {
    final saved = supabase.auth.currentUser?.userMetadata?[_metadataKey];
    if (saved is! List) return defaultMarketInstruments;
    final instruments = saved
        .map(MarketInstrument.fromJson)
        .whereType<MarketInstrument>()
        .map(
          (instrument) => instrument.symbol == '^STOXX50E'
              ? const MarketInstrument(symbol: 'DE30', name: 'DAX')
              : instrument,
        )
        .toList();
    return instruments.isEmpty ? defaultMarketInstruments : instruments;
  }

  @override
  Future<void> saveWatchlist(List<MarketInstrument> instruments) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const MarketFailure(MarketFailureKind.sessionExpired);
    }
    final metadata = <String, Object?>{
      ...?user.userMetadata,
      _metadataKey: [for (final instrument in instruments) instrument.toJson()],
    };
    await supabase.auth.updateUser(UserAttributes(data: metadata));
  }

  @override
  Future<MarketSeries> fetchSeries(
    MarketInstrument instrument,
    MarketPeriod period,
  ) async {
    final baseUrl = apiBaseUrl;
    if (baseUrl == null) {
      throw const MarketFailure(MarketFailureKind.unavailable);
    }
    final normalizedBase = baseUrl.toString().replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse('$normalizedBase/api/desktop/markets').replace(
      queryParameters: {'symbol': instrument.symbol, 'period': period.apiValue},
    );
    late http.Response response;
    try {
      response = await authorizedAgentRequest(
        supabase: supabase,
        accessTokenProvider: accessTokenProvider,
        send: (token) => _httpClient
            .get(uri, headers: {'authorization': 'Bearer $token'})
            .timeout(const Duration(seconds: 18)),
      );
    } on AuthRetryableFetchException {
      throw const MarketFailure(MarketFailureKind.unavailable);
    } on AuthException {
      throw const MarketFailure(MarketFailureKind.sessionExpired);
    } on Object {
      throw const MarketFailure(MarketFailureKind.unavailable);
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        throw const MarketFailure(MarketFailureKind.sessionExpired);
      case 403:
        throw const MarketFailure(MarketFailureKind.notAllowed);
      case 404:
        throw const MarketFailure(MarketFailureKind.symbolNotFound);
      default:
        throw const MarketFailure(MarketFailureKind.unavailable);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) throw const FormatException();
      final pointsJson = decoded['points'];
      if (pointsJson is! List) throw const FormatException();
      final points = <MarketPoint>[];
      for (final value in pointsJson) {
        if (value is! Map) continue;
        final timestamp = value['timestamp'];
        final close = value['close'];
        if (timestamp is num && close is num) {
          points.add(
            MarketPoint(
              time: DateTime.fromMillisecondsSinceEpoch(
                timestamp.toInt() * 1000,
                isUtc: true,
              ).toLocal(),
              close: close.toDouble(),
            ),
          );
        }
      }
      if (points.isEmpty) throw const FormatException();
      return MarketSeries(
        symbol: decoded['symbol'] as String? ?? instrument.symbol,
        name: decoded['name'] as String? ?? instrument.name,
        currency: decoded['currency'] as String? ?? '',
        exchange: decoded['exchange'] as String? ?? '',
        previousClose: (decoded['previousClose'] as num?)?.toDouble(),
        points: List.unmodifiable(points),
        updatedAt:
            DateTime.tryParse(
              decoded['updatedAt'] as String? ?? '',
            )?.toLocal() ??
            DateTime.now(),
      );
    } on Object {
      throw const MarketFailure(MarketFailureKind.invalidResponse);
    }
  }

  @override
  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
