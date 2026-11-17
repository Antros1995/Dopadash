import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../application/auth_controller.dart';
import 'auth_error_message.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/i18n/language_switch.dart';

enum _AuthMode { signIn, signUp, recover, updatePassword }

class AuthPage extends StatefulWidget {
  const AuthPage({
    required this.controller,
    required this.passwordRecovery,
    super.key,
  });

  final AuthController controller;
  final bool passwordRecovery;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  late _AuthMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.passwordRecovery
        ? _AuthMode.updatePassword
        : _AuthMode.signIn;
  }

  @override
  void didUpdateWidget(covariant AuthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.passwordRecovery && !oldWidget.passwordRecovery) {
      _mode = _AuthMode.updatePassword;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _title => switch (_mode) {
    _AuthMode.signIn => tr('Bentornato', 'Welcome back'),
    _AuthMode.signUp => tr('Crea il tuo spazio', 'Create your space'),
    _AuthMode.recover => tr('Recupera l\'accesso', 'Get back in'),
    _AuthMode.updatePassword => tr(
      'Scegli una nuova password',
      'Choose a new password',
    ),
  };

  String get _subtitle => switch (_mode) {
    _AuthMode.signIn => tr(
      'Accedi alla tua dashboard personale.',
      'Sign in to your personal dashboard.',
    ),
    _AuthMode.signUp => tr(
      'Un unico posto per le tue giornate.',
      'One place for your days.',
    ),
    _AuthMode.recover => tr(
      'Riceverai un link sicuro via email.',
      'You’ll get a secure link by email.',
    ),
    _AuthMode.updatePassword => tr(
      'Usa almeno 8 caratteri.',
      'Use at least 8 characters.',
    ),
  };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      switch (_mode) {
        case _AuthMode.signIn:
          await widget.controller.signIn(
            email: _email.text,
            password: _password.text,
          );
          break;
        case _AuthMode.signUp:
          final result = await widget.controller.signUp(
            email: _email.text,
            password: _password.text,
          );
          if (result.session == null) {
            _showMessage(
              tr(
                'Controlla la posta per confermare l\'account.',
                'Check your inbox to confirm the account.',
              ),
            );
          }
          break;
        case _AuthMode.recover:
          await widget.controller.sendPasswordReset(_email.text);
          _showMessage(tr('Link di recupero inviato.', 'Recovery link sent.'));
          setState(() => _mode = _AuthMode.signIn);
          break;
        case _AuthMode.updatePassword:
          await widget.controller.updatePassword(_password.text);
          _showMessage(tr('Password aggiornata.', 'Password updated.'));
          break;
      }
    } on Object catch (error) {
      _showMessage(authErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.danger : AppColors.green,
      ),
    );
  }

  void _changeMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Row(
              children: [
                if (wide) const Expanded(child: _AuthIntro()),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: _buildForm(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm() {
    final needsEmail = _mode != _AuthMode.updatePassword;
    final needsPassword = _mode != _AuthMode.recover;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (MediaQuery.sizeOf(context).width < 900) ...[
            const _BrandMark(),
            const SizedBox(height: AppSpacing.xxl),
          ],
          Text(_title, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(_subtitle, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xl),
          if (needsEmail) ...[
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) => value != null && value.contains('@')
                  ? null
                  : tr(
                      'Inserisci un indirizzo email valido.',
                      'Enter a valid email address.',
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (needsPassword) ...[
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: _mode == _AuthMode.updatePassword
                    ? tr('Nuova password', 'New password')
                    : 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  tooltip: _obscure
                      ? tr('Mostra password', 'Show password')
                      : tr('Nascondi password', 'Hide password'),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => (value?.length ?? 0) >= 8
                  ? null
                  : tr(
                      'La password deve avere almeno 8 caratteri.',
                      'The password needs at least 8 characters.',
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(switch (_mode) {
                    _AuthMode.signIn => tr('Accedi', 'Sign in'),
                    _AuthMode.signUp => tr('Crea account', 'Create account'),
                    _AuthMode.recover => tr('Invia link', 'Send link'),
                    _AuthMode.updatePassword => tr(
                      'Aggiorna password',
                      'Update password',
                    ),
                  }),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_mode == _AuthMode.signIn) ...[
            TextButton(
              onPressed: () => _changeMode(_AuthMode.recover),
              child: Text(tr('Password dimenticata?', 'Forgot your password?')),
            ),
            TextButton(
              onPressed: () => _changeMode(_AuthMode.signUp),
              child: Text(
                tr('Non hai un account? Registrati', 'No account? Sign up'),
              ),
            ),
          ] else if (_mode != _AuthMode.updatePassword)
            TextButton(
              onPressed: () => _changeMode(_AuthMode.signIn),
              child: Text(tr('Torna all\'accesso', 'Back to sign in')),
            ),
          const SizedBox(height: AppSpacing.md),
          const Center(child: LanguageSwitch()),
        ],
      ),
    );
  }
}

class _AuthIntro extends StatelessWidget {
  const _AuthIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(AppRadius.feature),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(light: true),
          const Spacer(),
          Text(
            tr('Le tue giornate,\nmesse a fuoco.', 'Your days,\nin focus.'),
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              color: Colors.white,
              fontSize: 52,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            tr(
              'Routine, progressi e strumenti personali in una dashboard calma e leggibile.',
              'Routines, progress and personal tools in a calm, readable dashboard.',
            ),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: .78),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.light = false});

  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white : AppColors.green;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.eco_rounded, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'DopaDash',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
