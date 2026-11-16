import 'dart:async';

import 'package:supabase/supabase.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/storage/auth_callback_location.dart';
import '../../core/storage/auth_session_store.dart';
import '../../core/sync/timeout_http_client.dart';

class AuthBootstrapResult {
  const AuthBootstrapResult({required this.isPasswordRecovery});

  final bool isPasswordRecovery;
}

class SupabaseClientService {
  SupabaseClientService._(this.client, this.sessionStore, this._transport);

  factory SupabaseClientService.create({
    required AppConfig config,
    required AuthSessionStore sessionStore,
    http.Client? httpClient,
  }) {
    final transport = TimeoutHttpClient(httpClient ?? http.Client());
    final client = SupabaseClient(
      _withoutTrailingSlash(config.supabaseUrl),
      config.supabasePublishableKey,
      httpClient: transport,
      authOptions: AuthClientOptions(
        autoRefreshToken: true,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: sessionStore,
      ),
    );
    return SupabaseClientService._(client, sessionStore, transport);
  }

  final SupabaseClient client;
  final AuthSessionStore sessionStore;
  final http.Client _transport;
  StreamSubscription<AuthState>? _subscription;

  Future<AuthBootstrapResult> initialize({Uri? launchUri}) async {
    _subscription = client.auth.onAuthStateChange.listen(
      (state) async {
        try {
          if (state.session == null) {
            await sessionStore.clearSession();
          } else {
            await sessionStore.writeSession(state.session!);
          }
        } on Object {
          // Authentication remains valid in-memory when storage is unavailable.
        }
      },
      onError: (Object error, StackTrace stack) {
        // Offline refresh errors must not escape the stream or erase the session.
        // GoTrue emits signedOut separately when a session is actually invalid.
      },
    );

    final currentUri = launchUri ?? Uri.base;
    if (_containsAuthCallback(currentUri)) {
      try {
        final response = await client.auth.getSessionFromUrl(currentUri);
        await sessionStore.writeSession(response.session);
        return AuthBootstrapResult(
          isPasswordRecovery:
              response.redirectType == AuthChangeEvent.passwordRecovery.name ||
              response.redirectType == 'recovery',
        );
      } finally {
        clearAuthCallbackFromAddressBar(currentUri);
      }
    }

    final stored = await sessionStore.readSession();
    if (stored != null) {
      try {
        final response = await client.auth.recoverSession(stored);
        if (response.session != null) {
          await sessionStore.writeSession(response.session!);
        }
      } on AuthRetryableFetchException {
        rethrow;
      } on Object {
        await sessionStore.clearSession();
      }
    }
    return const AuthBootstrapResult(isPasswordRecovery: false);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await client.dispose();
    _transport.close();
  }

  Future<void> ensureSession() async {
    await client.auth.getSession().timeout(const Duration(seconds: 20));
    if (client.auth.currentSession == null) throw AuthSessionMissingException();
  }

  static bool _containsAuthCallback(Uri uri) {
    const keys = <String>{
      'access_token',
      'code',
      'error',
      'error_code',
      'error_description',
      'refresh_token',
    };
    if (uri.queryParameters.keys.any(keys.contains)) return true;
    if (uri.fragment.isEmpty) return false;
    try {
      return Uri.splitQueryString(uri.fragment).keys.any(keys.contains);
    } on FormatException {
      return false;
    }
  }

  static String _withoutTrailingSlash(Uri uri) {
    final value = uri.toString();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
