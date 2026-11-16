import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/core/config/app_config.dart';

void main() {
  final normal = AppConfig.fromValues(
    supabaseUrl: 'https://project.supabase.co',
    supabasePublishableKey: 'sb_publishable_test',
    authRedirectUrl: 'http://localhost:7358/',
    personalAgentApiUrl: 'https://agent.example/',
  );
  test(
    'local preview uses the phone origin and preserves normal configuration and Supabase authentication',
    () {
      final preview = normal.forLocalPreview(
        Uri.parse('http://192.168.1.50:7359/#statistics'),
      );
      expect(
        preview.personalAgentApiUrl,
        Uri.parse('http://192.168.1.50:7359/'),
      );
      expect(preview.supabaseUrl, normal.supabaseUrl);
      expect(preview.supabasePublishableKey, normal.supabasePublishableKey);
      expect(normal.personalAgentApiUrl, Uri.parse('https://agent.example/'));
    },
  );
  test(
    'HTTP preview cannot silently redirect credentials to an external website',
    () {
      for (final origin in [
        'http://attacker.example/',
        'http://192.168.999.1/',
        'http://172.32.0.1/',
        'https://app.example/',
      ]) {
        expect(
          () => normal.forLocalPreview(Uri.parse(origin)),
          throwsA(isA<AppConfigException>()),
        );
      }
    },
  );
}
