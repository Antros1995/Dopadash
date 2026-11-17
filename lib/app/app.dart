import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/i18n/i18n.dart';
import '../features/auth/presentation/auth_gate.dart';
import 'dependencies.dart';
import 'theme.dart';

class PersonalDashboardApp extends StatelessWidget {
  const PersonalDashboardApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    // Switching language rebuilds the whole interface with the new texts.
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguage,
      builder: (context, language, _) => MaterialApp(
        title: 'DopaDash',
        debugShowCheckedModeBanner: false,
        theme: buildDesktopTheme(),
        locale: language.locale,
        supportedLocales: const [Locale('it'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: KeyedSubtree(
          key: ValueKey(language),
          child: AuthGate(dependencies: dependencies),
        ),
      ),
    );
  }
}
