import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/configuration_error_app.dart';

void main() {
  testWidgets('configuration screen explains the required setup', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ConfigurationErrorApp(message: 'Configurazione assente'),
    );

    expect(find.text('Configurazione richiesta'), findsOneWidget);
    expect(find.text('Configurazione assente'), findsOneWidget);
    expect(find.textContaining('Secret Key'), findsOneWidget);
  });
}
