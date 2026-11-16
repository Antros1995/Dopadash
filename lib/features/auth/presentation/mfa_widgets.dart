import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';

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
    decoration: const InputDecoration(
      labelText: 'Codice a 6 cifre',
      hintText: '000000',
      counterText: '',
      prefixIcon: Icon(Icons.password_rounded),
    ),
    validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
        ? null
        : 'Inserisci le 6 cifre dell’app Authenticator.',
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
