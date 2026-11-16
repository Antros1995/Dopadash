import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import '../../../core/sync/authorized_agent_request.dart';

class ExpenseSettings {
  const ExpenseSettings({
    this.sourceUrl = '',
    this.budgets = const {},
    this.defaultLimit = 1900,
    this.chartMetrics = const [],
  });
  final String sourceUrl;
  final Map<String, double> budgets;
  final double defaultLimit;
  final List<String> chartMetrics;
  double limitFor(String month) => budgets[month] ?? defaultLimit;
  factory ExpenseSettings.fromJson(Map<String, dynamic> row) => ExpenseSettings(
    sourceUrl: row['source_url'] as String? ?? '',
    budgets: {
      for (final e in ((row['monthly_budgets'] as Map?) ?? {}).entries)
        e.key.toString(): (e.value as num).toDouble(),
    },
    defaultLimit: (row['default_limit'] as num?)?.toDouble() ?? 1900,
    chartMetrics: List<String>.from(row['chart_metrics'] as List? ?? []),
  );
}

abstract interface class ExpenseRepository {
  Future<ExpenseSettings> loadSettings();
  Stream<ExpenseSettings> watchSettings();
  Future<ExpenseSettings> saveSettings({
    String? sourceUrl,
    String? month,
    double? limit,
    List<String>? chartMetrics,
  });
  Future<Uint8List> fetchWorkbook(String link);
  Future<Uri> beginMicrosoftConnect();
}

class SupabaseExpenseRepository implements ExpenseRepository {
  SupabaseExpenseRepository(this.client, this.apiBaseUrl);
  final SupabaseClient client;
  final Uri? apiBaseUrl;
  String get _user =>
      client.auth.currentUser?.id ??
      (throw StateError('Accedi al tuo account.'));
  @override
  Future<ExpenseSettings> loadSettings() async {
    final row = await client
        .from('monitoraggio_personale_expenses_settings')
        .select()
        .eq('user_id', _user)
        .maybeSingle();
    return row == null
        ? const ExpenseSettings()
        : ExpenseSettings.fromJson(row);
  }

  @override
  Stream<ExpenseSettings> watchSettings() => client
      .from('monitoraggio_personale_expenses_settings')
      .stream(primaryKey: ['user_id'])
      .eq('user_id', _user)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => ExpenseSettings.fromJson(rows.first));
  @override
  Future<ExpenseSettings> saveSettings({
    String? sourceUrl,
    String? month,
    double? limit,
    List<String>? chartMetrics,
  }) async {
    final row = await client.rpc(
      'monitoraggio_personale_save_expenses_settings',
      params: {
        'p_source_url': sourceUrl,
        'p_month': month,
        'p_limit': limit,
        'p_chart_metrics': chartMetrics,
      },
    );
    return ExpenseSettings.fromJson(
      Map<String, dynamic>.from((row as List).single as Map),
    );
  }

  @override
  Future<Uint8List> fetchWorkbook(String link) async {
    final local = ['localhost', '127.0.0.1'].contains(Uri.base.host);
    // Use the same protected backend on every device, including local preview.
    final uri =
        apiBaseUrl?.resolve('/api/desktop/expenses/workbook') ??
        (local ? Uri.base.resolve('/api/local/expenses/workbook') : null);
    if (uri == null) throw StateError('Servizio Excel non configurato.');
    Future<http.Response> send(String? token) => http
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            if (token != null) 'authorization': 'Bearer $token',
          },
          body: jsonEncode({'url': link}),
        )
        .timeout(const Duration(seconds: 45));
    final response = apiBaseUrl == null
        ? await send(null)
        : await authorizedAgentRequest(supabase: client, send: send);
    if (response.statusCode != 200) {
      if (response.statusCode == 404 && response.bodyBytes.isEmpty) {
        throw StateError(
          'Aggiorna il Worker Cloudflare per attivare la lettura OneDrive.',
        );
      }
      String message =
          'Excel non disponibile. Controlla che il link consenta il download.';
      try {
        message =
            (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['error']
                as String? ??
            message;
      } on Object {
        /* Preserve readable error. */
      }
      throw StateError(message);
    }
    return response.bodyBytes;
  }

  @override
  Future<Uri> beginMicrosoftConnect() async {
    final uri = apiBaseUrl?.resolve('/api/desktop/outlook/connect?files=read');
    if (uri == null) throw StateError('Accedi al tuo account.');
    final response = await authorizedAgentRequest(
      supabase: client,
      send: (token) => http
          .post(uri, headers: {'authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20)),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Collegamento Microsoft non disponibile. Verifica il Worker.',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final authorization = Uri.tryParse(
      decoded['authorizationUrl'] as String? ?? '',
    );
    if (authorization == null ||
        authorization.scheme != 'https' ||
        authorization.host != 'login.microsoftonline.com') {
      throw StateError('Risposta Microsoft non valida.');
    }
    if (!(authorization.queryParameters['scope'] ?? '')
        .split(' ')
        .any((s) => s.endsWith('/Files.Read'))) {
      throw StateError(
        'Aggiorna il Worker Cloudflare: manca il collegamento OneDrive in sola lettura.',
      );
    }
    return authorization;
  }
}
