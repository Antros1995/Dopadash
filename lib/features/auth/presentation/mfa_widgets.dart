import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';

class MfaCodeField extends StatelessWidget {
  const MfaCodeField({required this.controller, this.onSubmitted, super.key});

  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    autofillHints: const [AutofillHints.oneTimeCode],
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    maxLength: 6,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: tr('Codice a 6 cifre', '6-digit code'),
      hintText: '000000',
      counterText: '',
      prefixIcon: Icon(Icons.password_rounded),
    ),
    validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
        ? null
        : tr(
            'Inserisci le 6 cifre dell’app Authenticator.',
            'Enter the 6 digits from your Authenticator app.',
          ),
    onFieldSubmitted: onSubmitted,
  );
}

class MfaMessage extends StatelessWidget {
  const MfaMessage(this.message, {this.error = false, super.key});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      message,
      style: TextStyle(color: error ? AppColors.danger : AppColors.green),
    ),
  );
}
