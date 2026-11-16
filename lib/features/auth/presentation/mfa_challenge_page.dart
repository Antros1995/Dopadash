import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../application/mfa_controller.dart';
import 'auth_error_message.dart';
import 'mfa_widgets.dart';

/// This gate also wraps password recovery: an email link cannot skip MFA.
class MfaAccessGate extends StatelessWidget {
  const MfaAccessGate({
    required this.controller,
    required this.onSignOut,
    required this.child,
    super.key,
  });
  final MfaController controller;
  final Future<void> Function() onSignOut;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => controller.canEnter
        ? child
        : MfaChallengePage(controller: controller, onSignOut: onSignOut),
  );
}

class MfaChallengePage extends StatefulWidget {
  const MfaChallengePage({
    required this.controller,
    required this.onSignOut,
    super.key,
  });

  final MfaController controller;
  final Future<void> Function() onSignOut;

  @override
  State<MfaChallengePage> createState() => _MfaChallengePageState();
}

class _MfaChallengePageState extends State<MfaChallengePage> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  String? _factorId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final factors = widget.controller.status?.authenticators ?? [];
    if (factors.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.verify(_factorId ?? factors.first.id, _code.text);
      if (mounted) _code.clear();
    } on Object catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await widget.onSignOut();
    } on Object catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final factors = controller.status?.authenticators ?? [];
    final selected = factors.any((factor) => factor.id == _factorId)
        ? _factorId!
        : factors.firstOrNull?.id;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 44,
                          color: AppColors.green,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Verifica in due passaggi',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        if (controller.isChecking) ...[
                          const Text('Controllo della sicurezza dell’account…'),
                          const SizedBox(height: 20),
                          const Center(child: CircularProgressIndicator()),
                        ] else if (controller.hasError) ...[
                          const MfaMessage(
                            'Non riesco a verificare la sicurezza dell’account. Controlla la connessione e riprova.',
                            error: true,
                          ),
                          FilledButton(
                            onPressed: _busy ? null : controller.refresh,
                            child: const Text('Riprova'),
                          ),
                        ] else if (factors.isEmpty) ...[
                          const Text(
                            'Questo account usa un metodo di verifica non supportato da questa app. Usa un Authenticator TOTP o contatta l’amministratore del progetto.',
                          ),
                        ] else ...[
                          const Text(
                            'Apri la tua app Authenticator e inserisci il codice temporaneo per accedere.',
                          ),
                          const SizedBox(height: 20),
                          if (factors.length > 1) ...[
                            DropdownButtonFormField<String>(
                              initialValue: selected,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Authenticator',
                              ),
                              items: [
                                for (final factor in factors)
                                  DropdownMenuItem(
                                    value: factor.id,
                                    child: Text(
                                      factor.friendlyName ?? 'Authenticator',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                      _factorId = value;
                                      _code.clear();
                                    }),
                            ),
                            const SizedBox(height: 16),
                          ],
                          MfaCodeField(
                            controller: _code,
                            onSubmitted: (_) => _verify(),
                          ),
                          if (_error != null) MfaMessage(_error!, error: true),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _verify,
                            child: Text(
                              _busy
                                  ? 'Verifica in corso…'
                                  : 'Verifica e accedi',
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Non hai il telefono? Usa un altro Authenticator già collegato. Se li hai persi tutti, serve il recupero da parte dell’amministratore Supabase.',
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _busy ? null : _signOut,
                          child: const Text('Torna al login'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
