import 'auth_callback_location_stub.dart'
    if (dart.library.js_interop) 'auth_callback_location_web.dart'
    as implementation;

void clearAuthCallbackFromAddressBar(Uri uri) {
  implementation.clearAuthCallbackFromAddressBar(uri);
}
