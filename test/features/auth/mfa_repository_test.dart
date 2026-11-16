import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:monitoraggio_personale_desktop/features/auth/data/auth_repository.dart';
import 'package:supabase/supabase.dart';

const owner = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> user({String status = 'verified'}) => {
  'id': owner,
  'aud': 'authenticated',
  'app_metadata': {},
  'user_metadata': {},
  'created_at': '2026-01-01T00:00:00Z',
  'factors': [
    {
      'id': 'factor-id',
      'friendly_name': 'iPhone',
      'factor_type': 'totp',
      'status': status,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    },
  ],
};
Map<String, dynamic> tokens(String aal, {String status = 'verified'}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${part({'alg': 'HS256'})}.${part({'sub': owner, 'aal': aal, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.test',
    'refresh_token': 'test-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': user(status: status),
  };
}

http.Response json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  Future<SupabaseAuthRepository> repository(
    Future<http.Response> Function(http.Request) handler, {
    void Function(SupabaseClient)? onClient,
  }) async {
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-publishable',
      httpClient: MockClient(handler),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'test@example.test',
      password: 'password',
    );
    onClient?.call(client);
    return SupabaseAuthRepository(
      client,
      authRedirectUrl: Uri.parse('https://app.example/'),
    );
  }

  test(
    'refreshes factors and upgrades the stored session only after verification',
    () async {
      final requests = <http.Request>[];
      var verified = false;
      late SupabaseClient client;
      final repo = await repository((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/challenge')) {
          return json({
            'id': 'challenge-id',
            'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60,
          });
        }
        if (request.url.path.endsWith('/verify')) {
          expect(jsonDecode(request.body), {
            'challenge_id': 'challenge-id',
            'code': '123456',
          });
          verified = true;
          return json(tokens('aal2'));
        }
        return json(tokens(verified ? 'aal2' : 'aal1'));
      }, onClient: (value) => client = value);
      expect((await repo.loadMfaStatus()).needsVerification, isTrue);
      await repo.verifyAuthenticator('factor-id', '123456');
      expect(repo.cachedMfaStatus.isVerified, isTrue);
      expect(
        client.realtime.accessToken,
        client.auth.currentSession!.accessToken,
      );
      expect(
        requests.any(
          (r) => r.url.queryParameters['grant_type'] == 'refresh_token',
        ),
        isTrue,
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/challenge')).length,
        1,
      );
    },
  );

  for (final status in ['unverified', 'verified']) {
    test('cancellation never removes a $status factor incorrectly', () async {
      var deleted = 0;
      final repo = await repository((request) async {
        if (request.method == 'DELETE') {
          deleted++;
          return json({'id': 'factor-id'});
        }
        if (request.url.path.endsWith('/user')) {
          return json(user(status: status));
        }
        return json(tokens('aal2', status: status));
      });
      await repo.cancelAuthenticatorEnrollment('factor-id');
      expect(deleted, status == 'unverified' ? 1 : 0);
    });
  }
}
