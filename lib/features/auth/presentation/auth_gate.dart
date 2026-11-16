import 'package:flutter/material.dart';

import '../../../app/dependencies.dart';
import '../../shell/presentation/home_shell.dart';
import 'auth_page.dart';
import 'mfa_challenge_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dependencies.authController,
      builder: (context, _) {
        final auth = dependencies.authController;
        if (auth.isAuthenticated) {
          final content = auth.isPasswordRecovery
              ? AuthPage(controller: auth, passwordRecovery: true)
              : HomeShell(dependencies: dependencies);
          if (auth.mfa case final mfa?) {
            return MfaAccessGate(
              controller: mfa,
              onSignOut: auth.signOut,
              child: content,
            );
          }
          return content;
        }
        return AuthPage(
          controller: auth,
          passwordRecovery: auth.isPasswordRecovery,
        );
      },
    );
  }
}
