import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/auth/application/auth_controller.dart';
import 'package:monitoraggio_personale_desktop/features/auth/data/mfa_repository.dart';
import 'package:supabase/supabase.dart';

import 'mfa_fakes.dart';

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  AuthController controller(FakeMfaRepository repo, {bool recovery = false}) {
    final result = AuthController(
      repository: repo,
      initialPasswordRecovery: recovery,
    );
    addTearDown(() {
      result.dispose();
      unawaited(repo.changes.close());
    });
    return result;
  }

  test(
    'an unenrolled account enters only after the server check completes',
    () async {
      final repo = FakeMfaRepository()..loading = Completer<MfaStatus>();
      final auth = controller(repo);
      expect(auth.mfa!.canEnter, isFalse);
      repo.loading!.complete(repo.value);
      await settle();
      expect(auth.mfa!.canEnter, isTrue);
      expect(repo.loads, 1);
    },
  );

  test(
    'an MFA account requires a valid code; refresh events do not loop',
    () async {
      final repo = FakeMfaRepository(
        status: MfaStatus(factors: [factor('phone')], isVerified: false),
      );
      final auth = controller(repo);
      await settle();
      expect(auth.mfa!.needsVerification, isTrue);
      await expectLater(
        auth.mfa!.verify('phone', '000000'),
        throwsA(isA<AuthException>()),
      );
      expect(auth.mfa!.canEnter, isFalse);
      await auth.mfa!.verify('phone', '123456');
      expect(auth.mfa!.canEnter, isTrue);
      repo.emit(AuthChangeEvent.tokenRefreshed, session(aal: 'aal2'));
      await settle();
      expect(repo.loads, 1);
    },
  );

  test(
    'stale cached factors never bypass a fresh server MFA requirement',
    () async {
      final repo = FakeMfaRepository()..loading = Completer<MfaStatus>();
      final auth = controller(repo);
      repo.value = MfaStatus(factors: [factor('phone')], isVerified: false);
      repo.loading!.complete(repo.value);
      await settle();
      expect(auth.mfa!.canEnter, isFalse);
      expect(auth.mfa!.needsVerification, isTrue);
    },
  );

  test('network errors fail closed and the check can be retried', () async {
    final repo = FakeMfaRepository()
      ..loadError = const AuthException('Offline');
    final auth = controller(repo);
    await settle();
    expect(auth.mfa!.hasError, isTrue);
    expect(auth.mfa!.canEnter, isFalse);
    repo.loadError = null;
    await auth.mfa!.refresh();
    expect(auth.mfa!.canEnter, isTrue);
  });

  test('late account checks do not reopen the gate after sign out', () async {
    final repo = FakeMfaRepository()..loading = Completer<MfaStatus>();
    final auth = controller(repo);
    await auth.signOut();
    repo.loading!.complete(repo.value);
    await settle();
    expect(auth.isAuthenticated, isFalse);
    expect(auth.mfa!.canEnter, isFalse);
  });

  test('email password recovery cannot skip MFA', () async {
    final repo = FakeMfaRepository(
      status: MfaStatus(factors: [factor('phone')], isVerified: false),
    );
    final auth = controller(repo, recovery: true);
    await settle();
    await expectLater(
      auth.updatePassword('new-password'),
      throwsA(isA<AuthException>()),
    );
    expect(repo.passwordUpdates, 0);
    expect(auth.isPasswordRecovery, isTrue);
    await auth.mfa!.verify('phone', '123456');
    await auth.updatePassword('new-password');
    expect(repo.passwordUpdates, 1);
    expect(auth.isPasswordRecovery, isFalse);
  });

  test(
    'removal needs a fresh code and can use a backup authenticator',
    () async {
      final repo = FakeMfaRepository(
        status: MfaStatus(
          factors: [factor('lost'), factor('backup')],
          isVerified: true,
        ),
      );
      final auth = controller(repo);
      await settle();
      await expectLater(
        auth.mfa!.remove(
          factorId: 'lost',
          confirmationFactorId: 'backup',
          code: '000000',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(repo.removed, isEmpty);
      await auth.mfa!.remove(
        factorId: 'lost',
        confirmationFactorId: 'backup',
        code: '123456',
      );
      expect(repo.removed, ['lost']);
      expect(repo.verified, ['backup']);
      expect(auth.mfa!.status!.isEnabled, isTrue);
    },
  );

  test(
    'a verification finishing after logout cannot remove a factor',
    () async {
      final repo = FakeMfaRepository(
        status: MfaStatus(factors: [factor('phone')], isVerified: true),
      )..verifying = Completer<void>();
      final auth = controller(repo);
      await settle();
      final removal = auth.mfa!.remove(
        factorId: 'phone',
        confirmationFactorId: 'phone',
        code: '123456',
      );
      await auth.signOut();
      final assertion = expectLater(
        removal,
        throwsA(isA<AuthSessionMissingException>()),
      );
      repo.verifying!.complete();
      await assertion;
      expect(repo.removed, isEmpty);
      expect(auth.mfa!.canEnter, isFalse);
    },
  );

  test('enrollment is blocked until the account passes the MFA gate', () async {
    final repo = FakeMfaRepository(
      status: MfaStatus(factors: [factor('phone')], isVerified: false),
    );
    final auth = controller(repo);
    await settle();
    expect(() => auth.mfa!.enroll('backup'), throwsA(isA<AuthException>()));
    expect(repo.enrollments, 0);
  });
}
