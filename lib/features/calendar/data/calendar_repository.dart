import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import '../../../core/sync/authorized_agent_request.dart';

import '../domain/calendar_event.dart';

enum CalendarFailureKind {
  sessionExpired,
  notAllowed,
  outlookNotConnected,
  unavailable,
  invalidResponse,
}

class CalendarFailure implements Exception {
  const CalendarFailure(this.kind);

  final CalendarFailureKind kind;
}

abstract interface class CalendarRepository {
  bool get isConfigured;

  Future<CalendarDay> fetchDay(DateTime date);

  Future<Uri> beginOutlookConnect();

  void dispose();
}

class PersonalAgentCalendarRepository implements CalendarRepository {
  PersonalAgentCalendarRepository({
    required this.supabase,
    required this.apiBaseUrl,
    http.Client? httpClient,
    this.accessTokenProvider,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final SupabaseClient supabase;
  final Uri? apiBaseUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final String? Function()? accessTokenProvider;

  @override
  bool get isConfigured => apiBaseUrl != null;

  @override
  Future<CalendarDay> fetchDay(DateTime date) async {
    final baseUrl = apiBaseUrl;
    if (baseUrl == null) {
      throw const CalendarFailure(CalendarFailureKind.unavailable);
    }
    final normalizedBase = baseUrl.toString().replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse(
      '$normalizedBase/api/desktop/calendar',
    ).replace(queryParameters: {'date': _dateKey(date)});
    late http.Response response;
    try {
      response = await authorizedAgentRequest(
        supabase: supabase,
        accessTokenProvider: accessTokenProvider,
        send: (token) => _httpClient
            .get(uri, headers: {'authorization': 'Bearer $token'})
            .timeout(const Duration(seconds: 15)),
      );
    } on AuthRetryableFetchException {
      throw const CalendarFailure(CalendarFailureKind.unavailable);
    } on AuthException {
      throw const CalendarFailure(CalendarFailureKind.sessionExpired);
    } on Object {
      throw const CalendarFailure(CalendarFailureKind.unavailable);
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        throw const CalendarFailure(CalendarFailureKind.sessionExpired);
      case 403:
        throw const CalendarFailure(CalendarFailureKind.notAllowed);
      case 409:
        throw const CalendarFailure(CalendarFailureKind.outlookNotConnected);
      default:
        throw const CalendarFailure(CalendarFailureKind.unavailable);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('risposta non valida');
      }
      return CalendarDay.fromJson(decoded);
    } on FormatException {
      throw const CalendarFailure(CalendarFailureKind.invalidResponse);
    }
  }

  @override
  Future<Uri> beginOutlookConnect() async {
    final baseUrl = apiBaseUrl;
    if (baseUrl == null) {
      throw const CalendarFailure(CalendarFailureKind.unavailable);
    }
    final normalizedBase = baseUrl.toString().replaceFirst(RegExp(r'/$'), '');
    late http.Response response;
    try {
      response = await authorizedAgentRequest(
        supabase: supabase,
        accessTokenProvider: accessTokenProvider,
        send: (token) => _httpClient
            .post(
              Uri.parse('$normalizedBase/api/desktop/outlook/connect'),
              headers: {'authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 15)),
      );
    } on AuthRetryableFetchException {
      throw const CalendarFailure(CalendarFailureKind.unavailable);
    } on AuthException {
      throw const CalendarFailure(CalendarFailureKind.sessionExpired);
    } on Object {
      throw const CalendarFailure(CalendarFailureKind.unavailable);
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        throw const CalendarFailure(CalendarFailureKind.sessionExpired);
      case 403:
        throw const CalendarFailure(CalendarFailureKind.notAllowed);
      default:
        throw const CalendarFailure(CalendarFailureKind.unavailable);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?> ||
          decoded['authorizationUrl'] is! String) {
        throw const FormatException('risposta non valida');
      }
      final uri = Uri.tryParse(decoded['authorizationUrl']! as String);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('URL non valido');
      }
      return uri;
    } on FormatException {
      throw const CalendarFailure(CalendarFailureKind.invalidResponse);
    }
  }

  @override
  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
