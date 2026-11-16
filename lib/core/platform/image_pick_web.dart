import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'image_pick.dart';

bool get canPickImages => true;

/// Apre la scelta di una foto (su iPhone: fotocamera o libreria), la
/// rimpicciolisce al massimo a [maxSide] pixel di lato e la converte in JPEG,
/// così l'archivio non si riempie di immagini enormi.
Future<PickedImage?> pickImage({int maxSide = 1400}) {
  final done = Completer<PickedImage?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  input.style.display = 'none';
  web.document.body!.append(input);
  void finish(PickedImage? value) {
    input.remove();
    if (!done.isCompleted) done.complete(value);
  }

  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  input.addEventListener(
    'change',
    ((web.Event _) {
      final file = input.files?.item(0);
      if (file == null) return finish(null);
      () async {
        try {
          final bitmap = await web.window.createImageBitmap(file).toDart;
          final scale = math.min(
            1.0,
            maxSide / math.max(bitmap.width, bitmap.height),
          );
          final canvas = web.HTMLCanvasElement()
            ..width = (bitmap.width * scale).round()
            ..height = (bitmap.height * scale).round();
          (canvas.getContext('2d') as web.CanvasRenderingContext2D).drawImage(
            bitmap,
            0,
            0,
            canvas.width,
            canvas.height,
          );
          bitmap.close();
          final blob = Completer<web.Blob?>();
          canvas.toBlob(
            ((web.Blob? value) => blob.complete(value)).toJS,
            'image/jpeg',
            .86.toJS,
          );
          final encoded = await blob.future;
          if (encoded == null) return finish(null);
          final buffer = await encoded.arrayBuffer().toDart;
          finish(PickedImage(buffer.toDart.asUint8List()));
        } catch (_) {
          finish(null);
        }
      }();
    }).toJS,
  );
  input.click();
  return done.future;
}
