import 'package:supabase/supabase.dart';

String authErrorMessage(Object error) {
  if (error is AuthException) {
    final code = error.code ?? '';
    final normalized = error.message.toLowerCase();
    if (code == 'mfa_verification_failed' ||
        normalized.contains('invalid mfa code') ||
        normalized.contains('incorrect totp') ||
        normalized.contains('invalid totp')) {
      return 'Codice non valido o scaduto. Usa il nuovo codice dell’app Authenticator.';
    }
    if (code == 'over_request_rate_limit' ||
        code == 'over_mfa_request_rate_limit') {
      return 'Troppi tentativi. Attendi qualche istante e riprova.';
    }
    if (code == 'mfa_factor_name_conflict') {
      return 'Esiste già un Authenticator con questo nome. Scegli un altro nome.';
    }
    if (code == 'mfa_totp_enroll_not_enabled') {
      return 'Abilita Authenticator TOTP nelle impostazioni MFA del progetto Supabase.';
    }
    if (normalized.contains('invalid login credentials')) {
      return 'Email o password non corretti.';
    }
    if (normalized.contains('email not confirmed')) {
      return 'Conferma l’indirizzo email prima di accedere.';
    }
    if (normalized.contains('user already registered')) {
      return 'Esiste già un account con questa email.';
    }
    if (normalized.contains('password')) {
      return 'La password non rispetta i requisiti richiesti.';
    }
  }
  return 'Operazione non riuscita. Controlla la connessione e riprova.';
}
