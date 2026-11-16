import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:monitoraggio_personale_desktop/core/config/app_config.dart';
import 'package:monitoraggio_personale_desktop/core/storage/auth_session_store.dart';
import 'package:monitoraggio_personale_desktop/core/sync/authorized_agent_request.dart';
import 'package:monitoraggio_personale_desktop/core/sync/timeout_http_client.dart';
import 'package:monitoraggio_personale_desktop/data/services/supabase_client_service.dart';
import 'package:monitoraggio_personale_desktop/features/auth/application/auth_controller.dart';
import 'package:monitoraggio_personale_desktop/features/auth/data/auth_repository.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/data/calendar_repository.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import '../../features/investments/portfolio_test.dart' show MemoryStore;

const _owner = '11111111-1111-4111-8111-111111111111';
final _tokenExpiry =
    DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
String _token(int version) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': _owner, 'exp': _tokenExpiry, 'version': version})}.test';
}

http.Response _session(int version) => http.Response(
  jsonEncode({
    'access_token': _token(version),
    'refresh_token': 'refresh-$version',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': _owner,
      'aud': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-01-01T00:00:00Z',
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Future<SupabaseClient> _client(
  Future<http.Response> Function(http.Request) auth,
) async {
  final client = SupabaseClient(
    'https://test.supabase.co',
    'publishable-test',
    httpClient: MockClient(auth),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.signInWithPassword(
    email: 'test@example.test',
    password: 'test-password',
  );
  addTearDown(client.dispose);
  return client;
}

void main() {
  test(
    'sign-out during token recovery prevents the original request from being sent',
    () async {
      final recovered = Completer<http.Response>();
      final client = await _client(
        (r) async => r.url.queryParameters['grant_type'] == 'refresh_token'
            ? recovered.future
            : _session(1),
      );
      client.auth.currentSession!.expiresAt = 1;
      var requests = 0;
      final pending = expectLater(
        authorizedAgentRequest(
          supabase: client,
          send: (_) async {
            requests++;
            return http.Response('{}', 200);
          },
        ),
        throwsA(isA<AuthSessionMissingException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await client.auth.signOut(scope: SignOutScope.local);
      recovered.complete(_session(2));
      await pending;
      expect(requests, 0);
    },
  );
  test(
    'calendar and health requests share one expired-session refresh and use its new token',
    () async {
      var signIns = 0, refreshes = 0, requests = 0;
      final refreshed = Completer<http.Response>();
      final client = await _client((request) async {
        if (request.url.queryParameters['grant_type'] == 'refresh_token') {
          refreshes++;
          return refreshed.future;
        }
        signIns++;
        return _session(1);
      });
      client.auth.currentSession!.expiresAt = 1;
      final transport = MockClient((request) async {
        requests++;
        expect(request.headers['authorization'], 'Bearer ${_token(2)}');
        return request.url.path.endsWith('/calendar')
            ? http.Response(
                '{"date":"2026-10-19","timeZone":"Europe/Rome","events":[]}',
                200,
              )
            : http.Response(
                '{"configured":true,"connection":"CONNECTED"}',
                200,
              );
      });
      final calendar = PersonalAgentCalendarRepository(
        supabase: client,
        apiBaseUrl: Uri.parse('https://agent.example'),
        httpClient: transport,
      );
      final health = PersonalAgentFitbitRepository(
        supabase: client,
        apiBaseUrl: Uri.parse('https://agent.example'),
        httpClient: transport,
      );
      final first = calendar.fetchDay(DateTime(2026, 10, 19));
      final second = health.fetchDay(DateTime(2026, 10, 19));
      await Future<void>.delayed(Duration.zero);
      expect(refreshes, 1);
      expect(requests, 0);
      refreshed.complete(_session(2));
      await Future.wait([first, second]);
      expect(requests, 2);
      expect(signIns, 1);
    },
  );

  test(
    '401 refreshes and retries once; a persistent rejection never loops',
    () async {
      var refreshes = 0, requests = 0;
      final client = await _client((r) async {
        if (r.url.queryParameters['grant_type'] == 'refresh_token') {
          return _session(++refreshes + 1);
        }
        return _session(1);
      });
      final response = await authorizedAgentRequest(
        supabase: client,
        send: (token) async {
          requests++;
          if (requests == 2) expect(token, _token(2));
          return http.Response('{}', 401);
        },
      );
      expect(response.statusCode, 401);
      expect(refreshes, 1);
      expect(requests, 2);
    },
  );

  test(
    '403 is not retried and sign-out during a request cannot replay it',
    () async {
      var refreshes = 0, requests = 0;
      final client = await _client((r) async {
        refreshes++;
        return _session(1);
      });
      await authorizedAgentRequest(
        supabase: client,
        send: (_) async {
          requests++;
          return http.Response('{}', 403);
        },
      );
      expect(refreshes, 1);
      expect(requests, 1);
      await authorizedAgentRequest(
        supabase: client,
        send: (_) async {
          requests++;
          await client.auth.signOut(scope: SignOutScope.local);
          return http.Response('{}', 401);
        },
      );
      expect(requests, 2);
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'temporary auth stream errors preserve the signed-in screen and stored session',
    () async {
      var failRefresh = false;
      final store = MemoryStore();
      final service = SupabaseClientService.create(
        config: AppConfig.fromValues(
          supabaseUrl: 'https://test.supabase.co',
          supabasePublishableKey: 'publishable-test',
          authRedirectUrl: 'https://app.example/',
        ),
        sessionStore: AuthSessionStore(store),
        httpClient: MockClient(
          (r) async => failRefresh
              ? http.Response(
                  '{"message":"temporary failure"}',
                  503,
                  headers: {'content-type': 'application/json'},
                )
              : _session(1),
        ),
      );
      await service.initialize(launchUri: Uri.parse('https://app.example/'));
      final auth = AuthController(
        repository: SupabaseAuthRepository(
          service.client,
          authRedirectUrl: Uri.parse('https://app.example/'),
        ),
      );
      addTearDown(() async {
        auth.dispose();
        await service.dispose();
      });
      await auth.signIn(email: 'test@example.test', password: 'test-password');
      await Future<void>.delayed(Duration.zero);
      expect(auth.isAuthenticated, isTrue);
      final original = await service.sessionStore.readSession();
      failRefresh = true;
      await expectLater(
        service.client.auth.refreshSession(),
        throwsA(isA<AuthException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(auth.isAuthenticated, isTrue);
      expect(await service.sessionStore.readSession(), original);
      failRefresh = false;
      await service.client.auth.refreshSession();
      expect(auth.isAuthenticated, isTrue);
    },
  );

  test('stalled response headers and bodies both time out', () async {
    final pending = Completer<http.StreamedResponse>();
    final headers = TimeoutHttpClient(
      _Transport((_) => pending.future),
      timeout: const Duration(seconds: 2),
    );
    await expectLater(
      headers.get(Uri.parse('https://test.example/')),
      throwsA(isA<TimeoutException>()),
    );
    pending.complete(http.StreamedResponse(const Stream.empty(), 200));
    final bytes = StreamController<List<int>>();
    final body = TimeoutHttpClient(
      _Transport((_) async => http.StreamedResponse(bytes.stream, 200)),
      timeout: const Duration(seconds: 2),
    );
    final request = body.get(Uri.parse('https://test.example/'));
    final second = expectLater(request, throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(Duration.zero);
    bytes.add([1]);
    await second;
    headers.close();
    body.close();
    unawaited(bytes.close());
  });
}

class _Transport extends http.BaseClient {
  _Transport(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
