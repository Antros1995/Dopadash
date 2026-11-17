import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../storage/key_value_store.dart';

/// The two interface languages. Italian is the original one.
enum AppLanguage {
  italian('it', 'Italiano'),
  english('en', 'English');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  Locale get locale => Locale(code);

  static AppLanguage? fromCode(String? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }
}

/// The language the interface is shown in.
///
/// It starts as Italian so that tests and code that runs before startup keep
/// the original texts; [loadAppLanguage] picks the real one when the app starts.
final ValueNotifier<AppLanguage> appLanguage = ValueNotifier(
  AppLanguage.italian,
);

bool get isEnglish => appLanguage.value == AppLanguage.english;

/// Returns the text for the current language: `tr('Panoramica', 'Overview')`.
///
/// Each Italian text sits next to its English version, so a translation can't
/// get lost or drift away from the text it belongs to.
String tr(String italian, String english) => isEnglish ? english : italian;

/// Italian writes decimals with a comma ("4,9"); English keeps the point.
String decimal(String value) => isEnglish ? value : value.replaceAll('.', ',');

/// Groups thousands: "6.598" in Italian, "6,598" in English.
String thousands(int value) {
  final separator = isEnglish ? ',' : '.';
  return value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => separator,
  );
}

const _languageKey = 'dopadash.language';

/// Sets [appLanguage] from the saved choice, or from the device language the
/// first time: Italian devices get Italian, everybody else English.
Future<void> loadAppLanguage(KeyValueStore store) async {
  String? saved;
  try {
    saved = await store.read(_languageKey);
  } on Object {
    saved = null;
  }
  appLanguage.value =
      AppLanguage.fromCode(saved) ??
      (PlatformDispatcher.instance.locale.languageCode == 'it'
          ? AppLanguage.italian
          : AppLanguage.english);
}

/// Switches the interface language and remembers the choice on this device.
Future<void> setAppLanguage(AppLanguage language, KeyValueStore store) async {
  appLanguage.value = language;
  try {
    await store.write(_languageKey, language.code);
  } on Object {
    // The switch still works for this session if the device can't save it.
  }
}
