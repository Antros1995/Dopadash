import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase/supabase.dart';

import '../../../app/theme.dart';
import '../application/mfa_controller.dart';
import 'auth_error_message.dart';
import 'mfa_widgets.dart';

class MfaSettingsDialog extends StatefulWidget {
  const MfaSettingsDialog({required this.controller, super.key});
  final MfaController controller;

  @override
  State<MfaSettingsDialog> createState() => _MfaSettingsDialogState();
}

class _MfaSettingsDialogState extends State<MfaSettingsDialog> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  AuthMFAEnrollResponse? _enrollment;
  Factor? _removing;
  String? _confirmationFactorId;
  String? _message;
  bool _error = false;
  bool _busy = false;
  bool _showSecret = false;
  late final String? _ownerId;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ownerId = widget.controller.userId;
    widget.controller.addListener(_accountChanged);
    _name.text =
        'Authenticator ${(widget.controller.status?.authenticators.length ?? 0) + 1}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run(widget.controller.refresh));
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_accountChanged);
    final pending = _enrollment;
    if (pending != null) {
      unawaited(
        widget.controller
            .cancelEnrollment(pending.id)
            .catchError((Object _) {}),
      );
    }
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _accountChanged() {
    if (widget.controller.userId == _ownerId || _closing) return;
    _closing = true;
    _enrollment = null;
    _code.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _error = false;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _message = authErrorMessage(error);
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enroll() => _run(() async {
    if (_name.text.trim().isEmpty) {
      setState(() {
        _message = 'Dai un nome a questo Authenticator.';
        _error = true;
      });
      return;
    }
    final enrollment = await widget.controller.enroll(_name.text);
    if (mounted && widget.controller.userId == _ownerId) {
      setState(() => _enrollment = enrollment);
    }
  });

  Future<void> _verify() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await _run(() async {
      await widget.controller.verify(_enrollment!.id, _code.text);
      // Clear the secret immediately after successful activation.
      _enrollment = null;
      _code.clear();
      _showSecret = false;
      await widget.controller.refresh();
      if (mounted) {
        setState(() {
          _message =
              'Authenticator attivato. Ai prossimi accessi verrà richiesto il codice.';
          _name.text =
              'Authenticator ${(widget.controller.status?.authenticators.length ?? 0) + 1}';
        });
      }
    });
  }

  Future<void> _cancel() => _run(() async {
    if (_enrollment case final pending?) {
      await widget.controller.cancelEnrollment(pending.id);
    }
    if (!mounted) return;
    setState(() {
      _enrollment = null;
      _removing = null;
      _showSecret = false;
      _code.clear();
    });
    await widget.controller.refresh();
  });

  Future<void> _remove() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await _run(() async {
      await widget.controller.remove(
        factorId: _removing!.id,
        confirmationFactorId: _confirmationFactorId!,
        code: _code.text,
      );
      if (mounted) {
        setState(() {
          _removing = null;
          _code.clear();
          _message = widget.controller.status?.isEnabled == true
              ? 'Authenticator rimosso.'
              : 'Verifica in due passaggi disattivata.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final status = widget.controller.status;
      final factors = status?.authenticators ?? [];
      final totp = _enrollment?.totp;
      return PopScope(
        canPop: !_busy,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 540,
              maxHeight: MediaQuery.sizeOf(context).height - 64,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          color: AppColors.green,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Sicurezza account',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          tooltip: 'Chiudi',
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      status?.isEnabled == true
                          ? 'Verifica in due passaggi attiva'
                          : 'Proteggi l’accesso con un secondo passaggio',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Dopo email e password userai un codice temporaneo dalla tua app Authenticator.',
                    ),
                    if (widget.controller.hasError) ...[
                      const MfaMessage(
                        'Impossibile aggiornare lo stato di sicurezza. Riprova prima di continuare.',
                        error: true,
                      ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(widget.controller.refresh),
                        child: const Text('Aggiorna stato'),
                      ),
                    ] else if (totp != null) ...[
                      const SizedBox(height: 20),
                      const Text(
                        '1. Aggiungi un account nella tua app Authenticator e scansiona questo QR.',
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: QrImageView(
                          data: totp.uri,
                          size: 200,
                          backgroundColor: Colors.white,
                          semanticsLabel: 'QR di configurazione Authenticator',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Se stai usando lo stesso iPhone, scegli l’inserimento manuale nell’Authenticator e usa questa chiave.',
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _showSecret = !_showSecret),
                        icon: Icon(
                          _showSecret
                              ? Icons.visibility_off_outlined
                              : Icons.key_outlined,
                        ),
                        label: Text(
                          _showSecret
                              ? 'Nascondi chiave'
                              : 'Mostra chiave manuale',
                        ),
                      ),
                      if (_showSecret) ...[
                        SelectableText(
                          totp.secret,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tipo: codice temporaneo (TOTP). Conserva la chiave in un luogo sicuro e non condividerla.',
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        '2. Inserisci il codice generato per confermare l’attivazione.',
                      ),
                      const SizedBox(height: 12),
                      MfaCodeField(
                        controller: _code,
                        onSubmitted: (_) => _verify(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _verify,
                        child: const Text('Conferma e attiva'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _cancel,
                        child: const Text('Annulla configurazione'),
                      ),
                    ] else if (_removing != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Rimuovere ${_removing!.friendlyName ?? 'questo Authenticator'}?',
                      ),
                      if (factors.length == 1)
                        const MfaMessage(
                          'È l’ultimo Authenticator: rimuovendolo disattiverai la verifica in due passaggi.',
                          error: true,
                        ),
                      const Text(
                        'Conferma con un nuovo codice da uno degli Authenticator collegati.',
                      ),
                      const SizedBox(height: 12),
                      if (factors.length > 1) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _confirmationFactorId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Authenticator per confermare',
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
                                  _confirmationFactorId = value;
                                  _code.clear();
                                }),
                        ),
                        const SizedBox(height: 12),
                      ],
                      MfaCodeField(
                        controller: _code,
                        onSubmitted: (_) => _remove(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _remove,
                        child: const Text('Conferma rimozione'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _cancel,
                        child: const Text('Annulla'),
                      ),
                    ] else ...[
                      for (final factor in factors)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.phonelink_lock_outlined,
                                color: AppColors.green,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  factor.friendlyName ?? 'Authenticator',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Rimuovi Authenticator',
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _message = null;
                                        _removing = factor;
                                        _confirmationFactorId = factor.id;
                                        _code.clear();
                                      }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      if (status?.pendingFactors.isNotEmpty == true) ...[
                        const SizedBox(height: 16),
                        const Text('Configurazioni non completate'),
                        for (final factor in status!.pendingFactors)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  factor.friendlyName ??
                                      'Authenticator non verificato',
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                        await widget.controller
                                            .cancelEnrollment(factor.id);
                                        await widget.controller.refresh();
                                      }),
                                child: const Text('Elimina'),
                              ),
                            ],
                          ),
                      ],
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _name,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Nome Authenticator',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy || !widget.controller.canEnter
                            ? null
                            : _enroll,
                        icon: const Icon(Icons.add),
                        label: Text(
                          factors.isEmpty
                              ? 'Attiva verifica in due passaggi'
                              : 'Aggiungi Authenticator di riserva',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Puoi collegare un secondo Authenticator come riserva. Se perdi tutti i dispositivi, il recupero richiede l’intervento dell’amministratore Supabase.',
                      ),
                    ],
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(),
                      ),
                    if (_message != null) MfaMessage(_message!, error: _error),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
