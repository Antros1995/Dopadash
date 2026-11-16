import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/configuration_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final dependencies = await AppBootstrap.initialize();
    runApp(PersonalDashboardApp(dependencies: dependencies));
  } on Object catch (error) {
    runApp(ConfigurationErrorApp(message: error.toString()));
  }
}
