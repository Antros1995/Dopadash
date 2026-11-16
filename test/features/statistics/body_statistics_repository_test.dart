import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/data/body_statistics_repository.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/domain/body_statistics.dart';

const owner = '11111111-1111-4111-8111-111111111111';
Future<SupabaseClient> authenticatedClient(
  Future<http.Response> Function(http.Request) handler,
) async {
  final token =
      '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': owner, 'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})))}.test';
  final client = SupabaseClient(
    'https://test.supabase.co',
    'publishable-test',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      if (request.url.path.startsWith('/auth/')) {
        return http.Response(
          jsonEncode({
            'access_token': token,
            'refresh_token': 'test',
            'token_type': 'bearer',
            'expires_in': 86400,
            'user': {
              'id': owner,
              'aud': 'authenticated',
              'email': 'owner@example.test',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final response = await handler(request);
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: request,
        reasonPhrase: response.reasonPhrase,
      );
    }),
  );
  await client.auth.signInWithPassword(
    email: 'owner@example.test',
    password: 'test-password',
  );
  return client;
}

Map<String, dynamic> snapshot(String date, String synced, {double? hrv}) => {
  'date': date,
  'source': 'fitbit',
  'syncedAt': synced,
  'finalized': true,
  'heartRateVariabilityMs': hrv,
};

void main() {
  test(
    'history imports one newest snapshot per date with owner, source and sync timestamp',
    () async {
      final writes = <http.Request>[];
      final client = await authenticatedClient((r) async {
        writes.add(r);
        return http.Response('', 201);
      });
      addTearDown(client.dispose);
      final repo = SupabaseBodyStatisticsRepository(
        client,
        historySource: () async => [
          snapshot('2026-10-01', '2026-10-02T12:00:00Z', hrv: 40),
          snapshot('2026-10-01', '2026-10-01T12:00:00Z', hrv: 10),
          {
            ...snapshot('2026-09-01', '2026-09-02T12:00:00Z'),
            'source': 'other-device',
          },
        ],
      );
      await repo.syncHistory();
      final rows = jsonDecode(writes.single.body) as List;
      expect(rows.length, 1);
      expect(rows.single['user_id'], owner);
      expect(rows.single['payload']['heartRateVariabilityMs'], 40);
      expect(
        writes.single.url.queryParameters['on_conflict'],
        'user_id,day,source',
      );
      expect(writes.single.headers['authorization'], startsWith('Bearer '));
    },
  );
  test(
    'historical reads paginate beyond the default server page and always scope the owner',
    () async {
      final requests = <http.Request>[];
      final client = await authenticatedClient((r) async {
        requests.add(r);
        final offset = int.parse(r.url.queryParameters['offset'] ?? '0');
        return http.Response(
          jsonEncode([
            for (var i = offset; i < (offset == 0 ? 500 : 502); i++)
              {
                'payload': snapshot(
                  statsKey(DateTime.utc(2024).add(Duration(days: i))),
                  '2026-10-17T12:00:00Z',
                ),
              },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.dispose);
      final days = await SupabaseBodyStatisticsRepository(client).loadDays();
      expect(days.length, 502);
      expect(requests.length, 2);
      expect(
        requests.every((r) => r.url.queryParameters['user_id'] == 'eq.$owner'),
        isTrue,
      );
    },
  );
  test(
    'day recovery persists completed days, stops on cancellation, and rejects wrong dates',
    () async {
      final writes = <http.Request>[];
      final client = await authenticatedClient((r) async {
        writes.add(r);
        return http.Response('', 201);
      });
      addTearDown(client.dispose);
      var stop = false;
      final repo = SupabaseBodyStatisticsRepository(
        client,
        daySource: (d) async => snapshot(statsKey(d), '2026-10-17T12:00:00Z'),
      );
      await repo.recoverDays(
        [DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 2)],
        cancelled: () => stop,
        onProgress: (done, total) {
          stop = true;
        },
      );
      expect(writes.length, 1);
      expect(jsonDecode(writes.single.body)['day'], '2026-10-01');
      final wrong = SupabaseBodyStatisticsRepository(
        client,
        daySource: (d) async => snapshot('2020-01-01', '2026-10-17T12:00:00Z'),
      );
      await expectLater(
        wrong.recoverDays(
          [DateTime.utc(2026, 10, 1)],
          cancelled: () => false,
          onProgress: (_, _) {},
        ),
        throwsStateError,
      );
      expect(writes.length, 1);
    },
  );
  test(
    'emotion history reads all pages from the personal diary scoped to the owner',
    () async {
      final requests = <http.Request>[];
      final client = await authenticatedClient((request) async {
        requests.add(request);
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        return http.Response(
          jsonEncode([
            for (var i = offset; i < (offset == 0 ? 500 : 502); i++)
              {
                'id': 'emotion-$i',
                'reference_date': '2026-10-01',
                'emotion': i.isEven ? 'calm' : 'happy',
                'intensity': 4,
                'energy': 'medium',
                'recorded_at': '2026-10-01T21:00:00Z',
              },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.dispose);
      final entries = await SupabaseBodyStatisticsRepository(
        client,
      ).loadPerceptions();
      expect(entries.length, 502);
      expect(entries.first.intensity, 4);
      expect(entries.first.date, DateTime.utc(2026, 10, 1));
      expect(requests.length, 2);
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.url.path, '/rest/v1/emotion_entries');
        expect(request.url.queryParameters['user_id'], 'eq.$owner');
        expect(
          request.url.queryParameters['order'],
          'reference_date.asc.nullslast,recorded_at.asc.nullslast,id.asc.nullslast',
        );
        expect(
          request.url.queryParameters.containsKey('experiment_id'),
          isFalse,
        );
      }
    },
  );
  test(
    'reads and writes refuse to run without an authenticated user',
    () async {
      final client = SupabaseClient(
        'https://test.supabase.co',
        'publishable-test',
      );
      addTearDown(client.dispose);
      final repo = SupabaseBodyStatisticsRepository(client);
      await expectLater(repo.loadDays(), throwsStateError);
      await expectLater(repo.loadPerceptions(), throwsStateError);
      await expectLater(repo.savePreferences({}), throwsStateError);
    },
  );
}
