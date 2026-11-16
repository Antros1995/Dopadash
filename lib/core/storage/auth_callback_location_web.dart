import 'package:web/web.dart' as web;

const _authParameters = <String>{
  'access_token',
  'code',
  'error',
  'error_code',
  'error_description',
  'expires_in',
  'refresh_token',
  'token_type',
  'type',
};

void clearAuthCallbackFromAddressBar(Uri uri) {
  final queryParameters = <String, dynamic>{
    for (final entry in uri.queryParametersAll.entries)
      if (!_authParameters.contains(entry.key))
        entry.key: entry.value.length == 1 ? entry.value.first : entry.value,
  };
  final cleanUri = uri.replace(
    queryParameters: queryParameters.isEmpty ? null : queryParameters,
    fragment: '',
  );
  final path = cleanUri.path.isEmpty ? '/' : cleanUri.path;
  final relativeUrl = cleanUri.hasQuery ? '$path?${cleanUri.query}' : path;
  web.window.history.replaceState(null, '', relativeUrl);
}
