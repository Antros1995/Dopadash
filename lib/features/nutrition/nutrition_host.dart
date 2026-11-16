import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase/supabase.dart';

import '../../core/config/app_config.dart';
import 'nutrition_element_stub.dart'
    if (dart.library.js_interop) 'nutrition_element_web.dart';

/// Alimentazione: lo stesso componente web dell'app per iPhone
/// (web/dieta-component.js), che legge e scrive la tabella `diet_app_states`
/// con la sessione dell'utente. Qui gli si passa solo la configurazione.
class NutritionHost extends StatelessWidget {
  const NutritionHost({required this.client, required this.config, super.key});
  final SupabaseClient client;
  final AppConfig config;

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    // Il gettone di accesso si rinnova: il componente deve ricevere quello nuovo.
    stream: client.auth.onAuthStateChange,
    builder: (context, _) {
      final session = client.auth.currentSession;
      if (session == null) {
        return const Center(child: Text('Sessione scaduta. Accedi nuovamente.'));
      }
      final payload = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'supabaseUrl': config.supabaseUrl.toString(),
                'publishableKey': config.supabasePublishableKey,
                'accessToken': session.accessToken,
                'userId': session.user.id,
              }),
            ),
          )
          .replaceAll('=', '');
      return NutritionElement(
        key: ValueKey('diet-${session.user.id}'),
        configuration: payload,
      );
    },
  );
}
