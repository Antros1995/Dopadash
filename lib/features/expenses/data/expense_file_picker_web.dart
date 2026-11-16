import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<(String, Uint8List)?> pickExpenseFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.xlsx';
  final result = Completer<(String, Uint8List)?>();
  Future<void> readFile() async {
    try {
      final file = input.files?.item(0);
      if (file == null) {
        result.complete(null);
        return;
      }
      if (file.size > 25 * 1024 * 1024)
        throw const FormatException('Excel troppo grande.');
      final buffer = await file.arrayBuffer().toDart;
      result.complete((file.name, buffer.toDart.asUint8List()));
    } on Object catch (e) {
      result.completeError(e);
    }
  }

  input.addEventListener(
    'change',
    ((web.Event e) {
      unawaited(readFile());
    }).toJS,
  );
  input.addEventListener(
    'cancel',
    ((web.Event e) {
      if (!result.isCompleted) result.complete(null);
    }).toJS,
  );
  input.click();
  return result.future;
}
