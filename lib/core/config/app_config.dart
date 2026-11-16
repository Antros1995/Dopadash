class AppConfig {
  const AppConfig._({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.authRedirectUrl,
    required this.personalAgentApiUrl,
  });

  factory AppConfig.fromEnvironment() {
    final config = AppConfig.fromValues(
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: const String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
      authRedirectUrl: const String.fromEnvironment('AUTH_REDIRECT_URL'),
      personalAgentApiUrl: const String.fromEnvironment(
        'PERSONAL_AGENT_API_URL',
      ),
    );
    return const bool.fromEnvironment('LOCAL_API_PROXY')
        ? config.forLocalPreview(Uri.base)
        : config;
  }

  /// Opt-in local preview only: phones share the server's authenticated proxy.
  /// The normal desktop/production configuration is not changed.
  AppConfig forLocalPreview(Uri origin) {
    final host = origin.host;
    final parts = host.split('.').map(int.tryParse).toList();
    final privateIp =
        parts.length == 4 &&
        parts.every((n) => n != null && n >= 0 && n <= 255) &&
        (parts[0] == 10 ||
            (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31));
    if (origin.scheme != 'http' ||
        !(host == 'localhost' ||
            host == '127.0.0.1' ||
            host == '::1' ||
            privateIp)) {
      throw const AppConfigException(
        'Il proxy di anteprima è consentito solo sulla rete locale.',
      );
    }
    return AppConfig._(
      supabaseUrl: supabaseUrl,
      supabasePublishableKey: supabasePublishableKey,
      authRedirectUrl: authRedirectUrl,
      personalAgentApiUrl: Uri.parse('${origin.origin}/'),
    );
  }

  factory AppConfig.fromValues({
    required String supabaseUrl,
    required String supabasePublishableKey,
    required String authRedirectUrl,
    String personalAgentApiUrl = '',
  }) {
    final key = supabasePublishableKey.trim();
    if (_isMissingOrPlaceholder(key)) {
      throw const AppConfigException(
        'Manca SUPABASE_PUBLISHABLE_KEY. Usa il file locale dei dart-define.',
      );
    }
    final normalizedKey = key.toLowerCase();
    if (normalizedKey.startsWith('sb_secret_') ||
        normalizedKey.contains('service_role')) {
      throw const AppConfigException(
        'La chiave configurata non è adatta al client. Usa soltanto la Publishable Key.',
      );
    }

    return AppConfig._(
      supabaseUrl: _parseUrl(supabaseUrl, 'SUPABASE_URL'),
      supabasePublishableKey: key,
      authRedirectUrl: _parseUrl(authRedirectUrl, 'AUTH_REDIRECT_URL'),
      personalAgentApiUrl: _parseOptionalUrl(
        personalAgentApiUrl,
        'PERSONAL_AGENT_API_URL',
      ),
    );
  }

  final Uri supabaseUrl;
  final String supabasePublishableKey;
  final Uri authRedirectUrl;
  final Uri? personalAgentApiUrl;

  static Uri? _parseOptionalUrl(String rawValue, String variableName) {
    final value = rawValue.trim();
    if (_isMissingOrPlaceholder(value)) return null;
    return _parseUrl(value, variableName);
  }

  static Uri _parseUrl(String rawValue, String variableName) {
    final value = rawValue.trim();
    if (_isMissingOrPlaceholder(value)) {
      throw AppConfigException(
        'Manca $variableName. Usa il file locale dei dart-define.',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AppConfigException('$variableName non contiene un URL valido.');
    }
    final isLocalhost =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (uri.scheme != 'https' && !(isLocalhost && uri.scheme == 'http')) {
      throw AppConfigException(
        '$variableName deve usare HTTPS, salvo localhost in sviluppo.',
      );
    }
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
      throw AppConfigException(
        '$variableName non deve contenere query, frammenti o credenziali.',
      );
    }
    return uri;
  }

  static bool _isMissingOrPlaceholder(String value) {
    final upper = value.toUpperCase();
    return value.isEmpty ||
        upper == 'YOUR_PUBLISHABLE_KEY' ||
        upper.contains('YOUR_PROJECT_REF') ||
        upper.contains('YOUR_DESKTOP_APP') ||
        upper.contains('YOUR_PERSONAL_AGENT');
  }
}

class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}
