import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/features/wardrobe/wardrobe_page.dart';
import 'package:monitoraggio_personale_desktop/features/wardrobe/wardrobe_repository.dart';

class _Repo implements WardrobeRepository {
  _Repo(this.outfits);
  List<Outfit> outfits;
  final saved = <Outfit>[];

  @override
  Stream<void> watchChanges() => const Stream.empty();
  @override
  Future<List<Outfit>> load() async => outfits;
  @override
  Future<void> save(Outfit outfit, {Outfit? previous}) async {
    saved.add(outfit);
    outfits = [outfit, ...outfits.where((o) => o.id != outfit.id)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('layered outfits and reusing garments from the closet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _Repo([
      const Outfit(
        id: 'a',
        name: 'Inverno in città',
        seasons: {'Inverno'},
        pieces: [
          OutfitPiece(slot: OutfitSlot.head, path: 'u/a/cappello.jpg'),
          OutfitPiece(slot: OutfitSlot.outer, path: 'u/a/giubbino.jpg'),
          OutfitPiece(slot: OutfitSlot.top, path: 'u/a/maglia.jpg'),
          OutfitPiece(slot: OutfitSlot.bottom, path: 'u/a/jeans.jpg'),
          OutfitPiece(slot: OutfitSlot.shoes, path: 'u/a/stivali.jpg'),
        ],
      ),
      const Outfit(
        id: 'b',
        name: 'Ufficio',
        styles: {'Lavoro'},
        pieces: [
          OutfitPiece(slot: OutfitSlot.top, path: 'u/b/camicia.jpg'),
          // Stessi jeans dell'altro outfit: una sola foto.
          OutfitPiece(slot: OutfitSlot.bottom, path: 'u/a/jeans.jpg'),
        ],
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(body: WardrobePage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cosa ti metti oggi?'), findsOneWidget);
    expect(find.textContaining('2 outfit · 6 capi'), findsOneWidget);
    expect(find.text('5 capi'), findsOneWidget);

    // Filtro stagione.
    await tester.tap(find.text('❄️ Inverno').first);
    await tester.pumpAndSettle();
    expect(find.text('Ufficio'), findsNothing);
    expect(find.text('Inverno in città'), findsOneWidget);
    await tester.tap(find.text('Togli filtri'));
    await tester.pumpAndSettle();

    // Armadio: i jeans compaiono una volta, usati in 2 outfit.
    await tester.tap(find.text('👕 Armadio  6'));
    await tester.pumpAndSettle();
    expect(find.text('👖  Pantaloni  ·  1'), findsOneWidget);
    expect(find.text('in 2 outfit'), findsOneWidget);

    // Nuovo outfit solo con capi già salvati: niente nuove foto.
    await tester.tap(find.text('Nuovo outfit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi cappello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dall’armadio').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Dall’armadio → 🧢 Cappello'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.text('in 1 outfit'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi 1'));
    await tester.pumpAndSettle();
    // Due capi nello stesso strato: maglia e camicia insieme.
    await tester.tap(find.text('Dall’armadio').at(2));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Dall’armadio → 👕 Maglie e camicie'),
      findsOneWidget,
    );
    final tops = find.descendant(
      of: find.byType(Dialog).last,
      matching: find.text('in 1 outfit'),
    );
    expect(tops, findsNWidgets(2));
    await tester.tap(tops.at(0));
    await tester.tap(tops.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi 2'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 capi · puoi aggiungerne altri'),
      findsOneWidget,
    );
    await tester.tap(find.textContaining('Salva outfit · 3 capi'));
    await tester.pumpAndSettle();

    expect(repo.saved, hasLength(1));
    final pieces = repo.saved.single.pieces;
    expect(pieces.first.slot, OutfitSlot.head);
    expect(pieces.first.path, 'u/a/cappello.jpg');
    expect(pieces.where((p) => p.slot == OutfitSlot.top), hasLength(2));
    expect(pieces.every((p) => p.bytes == null), isTrue);
    expect(tester.takeException(), isNull);
  });
}
