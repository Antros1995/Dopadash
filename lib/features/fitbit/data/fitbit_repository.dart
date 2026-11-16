import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import '../../../core/sync/authorized_agent_request.dart';

import '../domain/fitbit_day.dart';

enum FitbitFailureKind {
  sessionExpired,
  notAllowed,
  unavailable,
  invalidResponse,
}

class FitbitFailure implements Exception {
  const FitbitFailure(this.kind);
  final FitbitFailureKind kind;
}

abstract interface class FitbitRepository {
  bool get isConfigured;
  Future<FitbitStatus> fetchDay(DateTime date);
  Future<FitbitStatus> saveMindfulnessMinutes(DateTime date, int? minutes);
  Future<Uri> beginConnect();
  void dispose();
}

class PersonalAgentFitbitRepository implements FitbitRepository {
  PersonalAgentFitbitRepository({
    required this.supabase,
    required this.apiBaseUrl,
    http.Client? httpClient,
    this.accessTokenProvider,
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  final SupabaseClient supabase;
  final Uri? apiBaseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final String? Function()? accessTokenProvider;

  @override
  bool get isConfigured => apiBaseUrl != null;

  /// Dated snapshots only. Undated trend arrays cannot be used as history.
  Future<Map<String, dynamic>?> fetchStatisticsDay(DateTime date) async {
    final response = await _request(
      'GET',
      '/api/desktop/fitbit',
      query: {'date': _dateKey(date)},
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FitbitFailure(FitbitFailureKind.invalidResponse);
    }
    final day = decoded['day'];
    return day is Map
        ? day.cast<String, dynamic>()
        : null;
  }

  Future<List<Map<String, dynamic>>> fetchStatisticsHistory() async {
    final response = await _request('GET', '/api/desktop/fitbit/history');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['days'] is! List) {
      throw const FitbitFailure(FitbitFailureKind.invalidResponse);
    }
    final days = (decoded['days'] as List)
        .map((d) => (d as Map).cast<String, dynamic>())
        .toList();
    // Refresh today's mutable snapshot through the established authenticated API.
    final current = await _request(
      'GET',
      '/api/desktop/fitbit',
      query: {'date': _dateKey(DateTime.now())},
    );
    final latest = jsonDecode(utf8.decode(current.bodyBytes)) as Map;
    if (latest['day'] is Map) {
      days.add((latest['day'] as Map).cast<String, dynamic>());
    }
    return days;
  }

  @override
  Future<FitbitStatus> fetchDay(DateTime date) async {
    final response = await _request(
      'GET',
      '/api/desktop/fitbit',
      query: {'date': _dateKey(date)},
    );
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) throw const FormatException();
      return FitbitStatus.fromJson(decoded);
    } on FormatException {
      debugPrint('Fitbit: risposta JSON non valida');
      throw const FitbitFailure(FitbitFailureKind.invalidResponse);
    }
  }

  @override
  Future<FitbitStatus> saveMindfulnessMinutes(
    DateTime date,
    int? minutes,
  ) async {
    final response = await _request(
      'POST',
      '/api/desktop/fitbit',
      body: {'date': _dateKey(date), 'mindfulnessMinutes': minutes},
    );
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) throw const FormatException();
      return FitbitStatus.fromJson(decoded);
    } on FormatException {
      throw const FitbitFailure(FitbitFailureKind.invalidResponse);
    }
  }

  @override
  Future<Uri> beginConnect() async {
    final response = await _request('POST', '/api/desktop/fitbit/connect');
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final raw = decoded is Map<String, Object?>
          ? decoded['authorizationUrl']
          : null;
      final uri = raw is String ? Uri.tryParse(raw) : null;
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException();
      }
      return uri;
    } on FormatException {
      throw const FitbitFailure(FitbitFailureKind.invalidResponse);
    }
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final base = apiBaseUrl;
    if (base == null) throw const FitbitFailure(FitbitFailureKind.unavailable);
    final uri = Uri.parse(
      '${base.toString().replaceFirst(RegExp(r'/$'), '')}$path',
    ).replace(queryParameters: query);
    late http.Response response;
    try {
      response = await authorizedAgentRequest(
        supabase: supabase,
        accessTokenProvider: accessTokenProvider,
        send: (token) =>
            (method == 'POST'
                    ? _client.post(
                        uri,
                        headers: {
                          'authorization': 'Bearer $token',
                          if (body != null) 'content-type': 'application/json',
                        },
                        body: body == null ? null : jsonEncode(body),
                      )
                    : _client.get(
                        uri,
                        headers: {'authorization': 'Bearer $token'},
                      ))
                .timeout(const Duration(seconds: 20)),
      );
    } on AuthRetryableFetchException {
      throw const FitbitFailure(FitbitFailureKind.unavailable);
    } on AuthException {
      throw const FitbitFailure(FitbitFailureKind.sessionExpired);
    } on Object catch (error) {
      debugPrint('Fitbit: richiesta non riuscita (${error.runtimeType})');
      throw const FitbitFailure(FitbitFailureKind.unavailable);
    }
    if (response.statusCode != 200) {
      String? errorCode;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, Object?> && decoded['error'] is String) {
          final code = decoded['error'] as String;
          if (RegExp(r'^[a-z_]+$').hasMatch(code)) errorCode = code;
        }
      } on Object {
        // Only the status code is needed if the server body is not JSON.
      }
      debugPrint(
        'Fitbit: HTTP ${response.statusCode}, codice ${errorCode ?? 'non disponibile'}',
      );
    }
    switch (response.statusCode) {
      case 200:
        return response;
      case 401:
        throw const FitbitFailure(FitbitFailureKind.sessionExpired);
      case 403:
        throw const FitbitFailure(FitbitFailureKind.notAllowed);
      default:
        throw const FitbitFailure(FitbitFailureKind.unavailable);
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
