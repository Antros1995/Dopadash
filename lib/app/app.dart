import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/auth/presentation/auth_gate.dart';
import 'dependencies.dart';
import 'theme.dart';

class PersonalDashboardApp extends StatelessWidget {
  const PersonalDashboardApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DopaDash',
      debugShowCheckedModeBanner: false,
      theme: buildDesktopTheme(),
      locale: const Locale('it'),
      supportedLocales: const [Locale('it'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: AuthGate(dependencies: dependencies),
    );
  }
}
