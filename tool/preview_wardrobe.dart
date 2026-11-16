// Anteprima della sezione Vestiti con capi finti (immagini disegnate al volo).
// Solo per controllare la grafica: non è importata da lib/main.dart.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/wardrobe/wardrobe_page.dart';
import 'package:monitoraggio_personale_desktop/features/wardrobe/wardrobe_repository.dart';

Future<Uint8List> _draw(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(300, 360);
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(300, 360), [
        color,
        Color.lerp(color, Colors.black, .25)!,
      ]),
  );
  // Una sagoma chiara al centro (le emoji non sono ancora caricate qui).
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(80, 90, 140, 180),
      const Radius.circular(36),
    ),
    Paint()..color = Colors.white.withValues(alpha: .28),
  );
  final image = await recorder.endRecording().toImage(300, 360);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class _Repo implements WardrobeRepository {
  _Repo(this.outfits);
  List<Outfit> outfits;
  @override
  Stream<void> watchChanges() => const Stream.empty();
  @override
  Future<List<Outfit>> load() async => outfits;
  @override
  Future<void> save(Outfit outfit, {Outfit? previous}) async =>
      outfits = [outfit, ...outfits.where((o) => o.id != outfit.id)];
  @override
  Future<void> delete(Outfit outfit) async =>
      outfits = outfits.where((o) => o.id != outfit.id).toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final img = <String, Uint8List>{
    'cappello': await _draw(const Color(0xFFB04A3A)),
    'giubbino': await _draw(const Color(0xFF3B4A5C)),
    'maglia': await _draw(const Color(0xFFD9C3A5)),
    'felpa': await _draw(const Color(0xFF7B8F6A)),
    'camicia': await _draw(const Color(0xFFEFEFF4)),
    'jeans': await _draw(const Color(0xFF3E5F8A)),
    'chino': await _draw(const Color(0xFFC9A77C)),
    'stivali': await _draw(const Color(0xFF5A3A2A)),
    'sneakers': await _draw(const Color(0xFFF2F2F2)),
    'sciarpa': await _draw(const Color(0xFF9A2E46)),
    'shorts': await _draw(const Color(0xFF6FA8C9)),
  };
  OutfitPiece p(OutfitSlot slot, String name) =>
      OutfitPiece(slot: slot, path: 'demo/$name', bytes: img[name]);
  final repo = _Repo([
    Outfit(
      id: '1',
      name: 'Inverno in città',
      seasons: const {'Inverno'},
      styles: const {'Casual'},
      pieces: [
        p(OutfitSlot.head, 'cappello'),
        p(OutfitSlot.outer, 'giubbino'),
        p(OutfitSlot.top, 'maglia'),
        p(OutfitSlot.bottom, 'jeans'),
        p(OutfitSlot.shoes, 'stivali'),
        p(OutfitSlot.accessory, 'sciarpa'),
      ],
    ),
    Outfit(
      id: '2',
      name: 'Ufficio',
      seasons: const {'Mezza stagione'},
      styles: const {'Lavoro'},
      pieces: [
        p(OutfitSlot.top, 'camicia'),
        p(OutfitSlot.bottom, 'chino'),
        p(OutfitSlot.shoes, 'sneakers'),
      ],
    ),
    Outfit(
      id: '3',
      name: 'Weekend',
      seasons: const {'Mezza stagione'},
      styles: const {'Casual'},
      pieces: [
        p(OutfitSlot.outer, 'giubbino'),
        p(OutfitSlot.top, 'felpa'),
        p(OutfitSlot.bottom, 'jeans'),
        p(OutfitSlot.shoes, 'sneakers'),
      ],
    ),
    Outfit(
      id: '4',
      name: 'Mare',
      seasons: const {'Estate'},
      styles: const {'Sportivo'},
      pieces: [
        p(OutfitSlot.top, 'maglia'),
        p(OutfitSlot.bottom, 'shorts'),
        p(OutfitSlot.shoes, 'sneakers'),
      ],
    ),
  ]);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildDesktopTheme(),
      home: Scaffold(body: WardrobePage(repository: repo)),
    ),
  );
}
