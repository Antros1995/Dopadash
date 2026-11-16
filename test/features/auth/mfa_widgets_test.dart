import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/auth/application/auth_controller.dart';
import 'package:monitoraggio_personale_desktop/features/auth/data/mfa_repository.dart';
import 'package:monitoraggio_personale_desktop/features/auth/presentation/mfa_challenge_page.dart';
import 'package:monitoraggio_personale_desktop/features/auth/presentation/mfa_settings_dialog.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase/supabase.dart';

import 'mfa_fakes.dart';

void main() {
  AuthController auth(FakeMfaRepository repository) {
    final controller = AuthController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await repository.changes.close();
    });
    return controller;
  }

  void size(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget child, {double keyboard = 0}) => MaterialApp(
    theme: buildDesktopTheme(),
    builder: (context, content) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.2),
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: content!,
    ),
    home: child,
  );
  Future<void> settings(WidgetTester tester, AuthController controller) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => MfaSettingsDialog(controller: controller.mfa!),
              ),
              child: const Text('Sicurezza'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sicurezza'));
    await tester.pumpAndSettle();
  }

  testWidgets('login keeps private content hidden until a valid code', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final controller = auth(
      FakeMfaRepository(
        status: MfaStatus(factors: [factor('iPhone')], isVerified: false),
      ),
    );
    await tester.pumpWidget(
      app(
        MfaAccessGate(
          controller: controller.mfa!,
          onSignOut: controller.signOut,
          child: const Scaffold(body: Text('Dati personali')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dati personali'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '000000');
    await tester.ensureVisible(find.text('Verifica e accedi'));
    await tester.tap(find.text('Verifica e accedi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Codice non valido'), findsOneWidget);
    expect(find.text('Dati personali'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verifica e accedi'));
    await tester.pumpAndSettle();
    expect(find.text('Dati personali'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1440, 900),
  ]) {
    testWidgets('MFA layout fits $viewport with large text and keyboard', (
      tester,
    ) async {
      size(tester, viewport);
      final controller = auth(
        FakeMfaRepository(
          status: MfaStatus(
            factors: [factor('Il mio Authenticator iPhone'), factor('Riserva')],
            isVerified: false,
          ),
        ),
      );
      await tester.pumpWidget(
        app(
          MfaAccessGate(
            controller: controller.mfa!,
            onSignOut: controller.signOut,
            child: const Text('Privato'),
          ),
          keyboard: viewport.width < 700 ? 260 : 0,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Verifica e accedi'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('enrollment shows local QR and a hidden manual key on iPhone', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final repository = FakeMfaRepository();
    final controller = auth(repository);
    await settings(tester, controller);
    await tester.ensureVisible(find.text('Attiva verifica in due passaggi'));
    await tester.tap(find.text('Attiva verifica in due passaggi'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('TESTONLYSECRET'), findsNothing);
    expect(controller.mfa!.status!.isEnabled, isFalse);
    await tester.ensureVisible(find.text('Mostra chiave manuale'));
    await tester.tap(find.text('Mostra chiave manuale'));
    await tester.pumpAndSettle();
    expect(find.text('TESTONLYSECRET'), findsOneWidget);
    await tester.ensureVisible(find.text('Nascondi chiave'));
    await tester.tap(find.text('Nascondi chiave'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Codice a 6 cifre'),
      '123456',
    );
    await tester.ensureVisible(find.text('Conferma e attiva'));
    await tester.tap(find.text('Conferma e attiva'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('TESTONLYSECRET'), findsNothing);
    expect(controller.mfa!.status!.isEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing incomplete setup cancels only that enrollment', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final repo = FakeMfaRepository();
    final controller = auth(repo);
    await settings(tester, controller);
    await tester.ensureVisible(find.text('Attiva verifica in due passaggi'));
    await tester.tap(find.text('Attiva verifica in due passaggi'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Chiudi'));
    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();
    expect(repo.cancelled, ['pending']);
    expect(repo.removed, isEmpty);
  });

  testWidgets('sign out closes setup and clears the visible secret', (
    tester,
  ) async {
    final repo = FakeMfaRepository();
    final controller = auth(repo);
    await settings(tester, controller);
    await tester.tap(find.text('Attiva verifica in due passaggi'));
    await tester.pumpAndSettle();
    await controller.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(MfaSettingsDialog), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported verified factors never open private content', (
    tester,
  ) async {
    final controller = auth(
      FakeMfaRepository(
        status: MfaStatus(
          factors: [factor('Phone', type: FactorType.phone)],
          isVerified: false,
        ),
      ),
    );
    await tester.pumpWidget(
      app(
        MfaAccessGate(
          controller: controller.mfa!,
          onSignOut: controller.signOut,
          child: const Text('Privato'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Privato'), findsNothing);
    expect(find.textContaining('non supportato'), findsOneWidget);
  });
}
