import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/core/i18n/i18n.dart';
import 'package:monitoraggio_personale_desktop/core/i18n/names.dart';
import 'package:monitoraggio_personale_desktop/core/storage/key_value_store.dart';
import 'package:monitoraggio_personale_desktop/core/utils/date_formatters.dart';
import 'package:monitoraggio_personale_desktop/features/auth/application/auth_controller.dart';
import 'package:monitoraggio_personale_desktop/features/auth/presentation/auth_page.dart';
import 'package:monitoraggio_personale_desktop/features/daily/domain/daily_models.dart';
import 'package:monitoraggio_personale_desktop/features/routines/domain/routine.dart';

import '../features/auth/mfa_fakes.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  tearDown(() => appLanguage.value = AppLanguage.italian);

  test('Italian is the default and keeps the original texts', () {
    expect(tr('Panoramica', 'Overview'), 'Panoramica');
    expect(sectionLabel('Sonno'), 'Sonno');
    expect(pageName(8), 'Quotidianità');
    expect(decimal('4.9'), '4,9');
    expect(thousands(6598), '6.598');
    expect(formatLongDate(DateTime(2026, 11, 16)), 'lunedì, 16 novembre 2026');
  });

  test('English switches texts, names, numbers and dates', () {
    appLanguage.value = AppLanguage.english;
    expect(tr('Panoramica', 'Overview'), 'Overview');
    expect(sectionLabel('Sonno'), 'Sleep');
    expect(sectionLabel('Nome inventato'), 'Nome inventato');
    expect(pageName(8), 'Daily');
    expect(decimal('4.9'), '4.9');
    expect(thousands(1234567), '1,234,567');
    expect(formatLongDate(DateTime(2026, 11, 16)), 'Monday, 16 November 2026');
    expect(DayMedal.platinum.label, 'Platinum');
    expect(DailyEmotion.calm.label, 'Calm');
    expect(
      buildDefaultRoutineHistory().map((r) => r.name),
      contains('Meditation'),
    );
  });

  test('the chosen language is saved and loaded again', () async {
    final store = _MemoryStore();
    await setAppLanguage(AppLanguage.english, store);
    appLanguage.value = AppLanguage.italian;
    await loadAppLanguage(store);
    expect(appLanguage.value, AppLanguage.english);
  });

  testWidgets('the sign-in page speaks English and offers the switch', (
    tester,
  ) async {
    appLanguage.value = AppLanguage.english;
    final controller = AuthController(repository: FakeMfaRepository());
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AuthPage(controller: controller, passwordRecovery: false),
      ),
    );
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(find.text('Italiano'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });
}
