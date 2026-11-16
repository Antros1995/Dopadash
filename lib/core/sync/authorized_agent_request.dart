import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

/// Manual Worker requests need the same on-demand refresh as Supabase queries.
/// A rejected token is retried once, only for the same signed-in account.
Future<http.Response> authorizedAgentRequest({
  required SupabaseClient supabase,
  required Future<http.Response> Function(String token) send,
  String? Function()? accessTokenProvider,
}) async {
  if (accessTokenProvider != null) {
    final token = accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw AuthSessionMissingException();
    }
    return send(token);
  }
  final session = await supabase.auth.getSession().timeout(
    const Duration(seconds: 20),
  );
  if (session == null || supabase.auth.currentUser?.id != session.user.id) {
    throw AuthSessionMissingException();
  }
  final response = await send(session.accessToken);
  if (response.statusCode != 401 ||
      supabase.auth.currentUser?.id != session.user.id) {
    return response;
  }
  var current = await supabase.auth.getSession().timeout(
    const Duration(seconds: 20),
  );
  if (current?.accessToken == session.accessToken) {
    current = (await supabase.auth.refreshSession().timeout(
      const Duration(seconds: 20),
    )).session;
  }
  if (current == null ||
      current.user.id != session.user.id ||
      supabase.auth.currentUser?.id != session.user.id) {
    return response;
  }
  return send(current.accessToken);
}
