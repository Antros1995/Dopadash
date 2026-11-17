import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/configuration_error_app.dart';
import 'core/i18n/i18n.dart';
import 'core/storage/key_value_store_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppLanguage(createKeyValueStore());
  try {
    final dependencies = await AppBootstrap.initialize();
    runApp(PersonalDashboardApp(dependencies: dependencies));
  } on Object catch (error) {
    runApp(ConfigurationErrorApp(message: error.toString()));
  }
}
