import 'dart:typed_data';

export 'image_pick_stub.dart' if (dart.library.js_interop) 'image_pick_web.dart';

/// Una foto scelta dall'utente, già rimpicciolita e in formato JPEG.
class PickedImage {
  const PickedImage(this.bytes);
  final Uint8List bytes;
  static const contentType = 'image/jpeg';
}
