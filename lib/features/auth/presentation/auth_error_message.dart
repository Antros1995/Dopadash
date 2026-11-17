import 'package:supabase/supabase.dart';
import '../../../core/i18n/i18n.dart';

String authErrorMessage(Object error) {
  if (error is AuthException) {
    final code = error.code ?? '';
    final normalized = error.message.toLowerCase();
    if (code == 'mfa_verification_failed' ||
        normalized.contains('invalid mfa code') ||
        normalized.contains('incorrect totp') ||
        normalized.contains('invalid totp')) {
      return tr(
        'Codice non valido o scaduto. Usa il nuovo codice dell’app Authenticator.',
        'Invalid or expired code. Use the new code from your Authenticator app.',
      );
    }
    if (code == 'over_request_rate_limit' ||
        code == 'over_mfa_request_rate_limit') {
      return tr(
        'Troppi tentativi. Attendi qualche istante e riprova.',
        'Too many attempts. Wait a moment and try again.',
      );
    }
    if (code == 'mfa_factor_name_conflict') {
      return tr(
        'Esiste già un Authenticator con questo nome. Scegli un altro nome.',
        'An Authenticator with this name already exists. Choose another name.',
      );
    }
    if (code == 'mfa_totp_enroll_not_enabled') {
      return tr(
        'Abilita Authenticator TOTP nelle impostazioni MFA del progetto Supabase.',
        'Enable TOTP Authenticator in the MFA settings of your Supabase project.',
      );
    }
    if (normalized.contains('invalid login credentials')) {
      return tr('Email o password non corretti.', 'Wrong email or password.');
    }
    if (normalized.contains('email not confirmed')) {
      return tr(
        'Conferma l’indirizzo email prima di accedere.',
        'Confirm your email address before signing in.',
      );
    }
    if (normalized.contains('user already registered')) {
      return tr(
        'Esiste già un account con questa email.',
        'An account with this email already exists.',
      );
    }
    if (normalized.contains('password')) {
      return tr(
        'La password non rispetta i requisiti richiesti.',
        'The password doesn’t meet the requirements.',
      );
    }
  }
  return tr(
    'Operazione non riuscita. Controlla la connessione e riprova.',
    'Something went wrong. Check the connection and try again.',
  );
}
