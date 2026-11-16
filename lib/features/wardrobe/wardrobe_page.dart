import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/platform/image_pick.dart';
import '../../core/presentation/responsive_layout.dart';
import '../daily/presentation/daily_widgets.dart';
import 'wardrobe_repository.dart';

// ------------------------------------------------------------------- stile

const _ink = Color(0xFF2B2622);
const _inkMuted = Color(0xFF7A6F66);
const _cream = Color(0xFFFBF7F2);
const _line = Color(0xFFEDE5DC);
const _accent = Color(0xFFE2725B);
const _accentSoft = Color(0xFFFCE9E3);

/// Colore di sfondo di un outfit, secondo la stagione.
List<Color> _seasonGradient(Set<String> seasons) {
  if (seasons.length == 1) {
    return switch (seasons.first) {
      'Estate' => const [Color(0xFFFFF3D9), Color(0xFFFFE2C6)],
      'Mezza stagione' => const [Color(0xFFF2F6E6), Color(0xFFE3EED8)],
      'Inverno' => const [Color(0xFFEAF2FC), Color(0xFFDCE6F8)],
      _ => const [Color(0xFFF6F1EB), Color(0xFFEDE6DE)],
    };
  }
  return const [Color(0xFFF6F1EB), Color(0xFFEDE6DE)];
}

Color _tagColor(String tag) => switch (tag) {
  'Estate' => const Color(0xFFE59A1A),
  'Mezza stagione' => const Color(0xFF6E9A3C),
  'Inverno' => const Color(0xFF3F7BD1),
  'Elegante' => const Color(0xFF8A5CC2),
  'Lavoro' => const Color(0xFF4F6D7A),
  'Casual' => const Color(0xFFE2725B),
  'Sportivo' => const Color(0xFF14A08A),
  _ => _inkMuted,
};

/// Vestiti: outfit composti a strati (cappello, giubbino, maglia, pantaloni,
/// scarpe, accessori) e l'armadio con tutti i capi già fotografati, da
/// riusare senza caricare di nuovo la foto.
class WardrobePage extends StatefulWidget {
  const WardrobePage({required this.repository, super.key});
  final WardrobeRepository repository;
  @override
  State<WardrobePage> createState() => WardrobePageState();
}

class WardrobePageState extends State<WardrobePage> {
  List<Outfit>? _outfits;
  Object? _error;
  String? _season, _style;
  bool _closet = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.repository.watchChanges().listen((_) => _load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  void showSection(String section) {
    setState(() {
      if (outfitSeasons.contains(section)) {
        _season = section;
      } else if (outfitStyles.contains(section)) {
        _style = section;
      } else {
        _season = _style = null;
      }
    });
  }

  Future<void> _load() async {
    try {
      final outfits = await widget.repository.load();
      if (mounted) {
        setState(() {
          _outfits = outfits;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static String newId() {
    final r = math.Random.secure();
    String hex(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
  }

  List<Garment> get _garments => Garment.collect(_outfits ?? const []);

  Future<void> _edit([
    Outfit? outfit,
    List<OutfitPiece> start = const [],
  ]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OutfitDialog(
        repository: widget.repository,
        original: outfit,
        garments: _garments,
        draft:
            outfit ??
            Outfit(
              id: newId(),
              seasons: {?_season},
              styles: {?_style},
              pieces: start,
            ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _surprise(List<Outfit> visible) async {
    if (visible.isEmpty) return;
    final edit = await showDialog<Outfit>(
      context: context,
      builder: (_) => _SurpriseDialog(outfits: visible),
    );
    if (edit != null && mounted) await _edit(edit);
  }

  Future<void> _openGarment(Garment garment) async {
    final create = await showDialog<bool>(
      context: context,
      builder: (_) => _GarmentDialog(garment: garment),
    );
    if (create == true && mounted) {
      await _edit(null, [garment.piece(garment.slot)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _outfits;
    final visible = [
      for (final o in all ?? const <Outfit>[])
        if ((_season == null || o.seasons.contains(_season)) &&
            (_style == null || o.styles.contains(_style)))
          o,
    ];
    final garments = _garments;
    final canCreate = canPickImages || garments.isNotEmpty;
    return ColoredBox(
      color: _cream,
      child: SingleChildScrollView(
        padding: pageInsets(context, const EdgeInsets.fromLTRB(24, 22, 24, 40)),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(
                  outfits: all?.length,
                  garments: garments.length,
                  onSurprise: visible.length > 1
                      ? () => _surprise(visible)
                      : null,
                  onCreate: canCreate ? () => _edit() : null,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _Tab(
                      label: '✨ Outfit',
                      count: all?.length,
                      selected: !_closet,
                      onTap: () => setState(() => _closet = false),
                    ),
                    const SizedBox(width: 8),
                    _Tab(
                      label: '👕 Armadio',
                      count: garments.length,
                      selected: _closet,
                      onTap: () => setState(() => _closet = true),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  DailyErrorBanner(onRetry: _load)
                else if (all == null)
                  const Padding(
                    padding: EdgeInsets.all(60),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                else if (_closet)
                  _Closet(
                    garments: garments,
                    onOpen: _openGarment,
                    onCreate: canCreate ? () => _edit() : null,
                  )
                else ...[
                  _Filters(
                    season: _season,
                    style: _style,
                    onSeason: (v) => setState(() => _season = v),
                    onStyle: (v) => setState(() => _style = v),
                  ),
                  const SizedBox(height: 18),
                  if (visible.isEmpty)
                    _Empty(
                      hasOutfits: all.isNotEmpty,
                      onCreate: canCreate ? () => _edit() : null,
                    )
                  else
                    LayoutBuilder(
                      builder: (context, box) {
                        final columns = math.max(
                          2,
                          (box.maxWidth / 260).floor(),
                        );
                        // A colonne, come una bacheca: ogni outfit va nella
                        // colonna più corta, così non restano buchi.
                        final lanes = List.generate(columns, (_) => <Outfit>[]);
                        final heights = List.filled(columns, 0.0);
                        for (final outfit in visible) {
                          var lane = 0;
                          for (var i = 1; i < columns; i++) {
                            if (heights[i] < heights[lane]) lane = i;
                          }
                          lanes[lane].add(outfit);
                          heights[lane] += _Composition.estimate(outfit) + 90;
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < columns; i++) ...[
                              if (i > 0) const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  children: [
                                    for (final outfit in lanes[i])
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: _OutfitCard(
                                          outfit: outfit,
                                          onTap: () => _edit(outfit),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- intestazione

class _Hero extends StatelessWidget {
  const _Hero({
    required this.outfits,
    required this.garments,
    required this.onSurprise,
    required this.onCreate,
  });
  final int? outfits;
  final int garments;
  final VoidCallback? onSurprise, onCreate;

  @override
  Widget build(BuildContext context) {
    final phone = usesPhoneLayout(context);
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onSurprise != null)
          OutlinedButton.icon(
            onPressed: onSurprise,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _ink,
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Text('🎲', style: TextStyle(fontSize: 16)),
            label: const Text(
              'Scegli per me',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        FilledButton.icon(
          onPressed: onCreate,
          style: FilledButton.styleFrom(
            backgroundColor: _ink,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(
            'Nuovo outfit',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'IL TUO ARMADIO',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w800,
            color: Color(0xFFB4533F),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Cosa ti metti oggi?',
          style: TextStyle(
            fontSize: phone ? 26 : 32,
            height: 1.1,
            letterSpacing: -.8,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          outfits == null
              ? 'Componi i tuoi outfit a strati, dalla testa ai piedi.'
              : '$outfits outfit · $garments capi · componi a strati, dalla testa ai piedi',
          style: const TextStyle(fontSize: 13.5, color: _inkMuted),
        ),
      ],
    );
    return Container(
      padding: EdgeInsets.all(phone ? 18 : 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE8DC), Color(0xFFFBD9E4), Color(0xFFE7E1FA)],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!phone)
            const Positioned(
              right: 0,
              top: -6,
              child: Text(
                '🧥👕👖👟',
                style: TextStyle(fontSize: 34, letterSpacing: -4),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [text, const SizedBox(height: 18), buttons],
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? _ink : Colors.white,
    borderRadius: BorderRadius.circular(30),
    child: InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          count == null ? label : '$label  $count',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : _ink,
          ),
        ),
      ),
    ),
  );
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.season,
    required this.style,
    required this.onSeason,
    required this.onStyle,
  });
  final String? season, style;
  final ValueChanged<String?> onSeason, onStyle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final s in outfitSeasons)
        _TagPill(
          tag: s,
          selected: season == s,
          onTap: () => onSeason(season == s ? null : s),
        ),
      Container(width: 1, height: 22, color: _line),
      for (final s in outfitStyles)
        _TagPill(
          tag: s,
          selected: style == s,
          onTap: () => onStyle(style == s ? null : s),
        ),
      if (season != null || style != null)
        TextButton(
          onPressed: () {
            onSeason(null);
            onStyle(null);
          },
          child: const Text('Togli filtri'),
        ),
    ],
  );
}

class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.tag,
    required this.selected,
    required this.onTap,
  });
  final String tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _tagColor(tag);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
            horizontal: 13,
            vertical: usesPhoneLayout(context) ? 9 : 7,
          ),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? color : _line),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: .3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            '${outfitTagEmoji[tag] ?? ''} $tag',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : _ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasOutfits, required this.onCreate});
  final bool hasOutfits;
  final VoidCallback? onCreate;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _line, width: 1.5),
    ),
    child: Column(
      children: [
        const Text('🧥', style: TextStyle(fontSize: 44)),
        const SizedBox(height: 10),
        Text(
          hasOutfits
              ? 'Nessun outfit con questi filtri.'
              : 'Il tuo primo outfit, a strati.',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasOutfits
              ? 'Togli un filtro oppure creane uno nuovo.'
              : 'Fotografa i capi uno per uno: maglia, giubbino, pantaloni, scarpe, cappello… Li ritroverai nell’armadio per riusarli.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: _inkMuted),
        ),
        if (onCreate != null) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreate,
            style: FilledButton.styleFrom(backgroundColor: _accent),
            icon: const Icon(Icons.add_a_photo_outlined, size: 17),
            label: const Text('Nuovo outfit'),
          ),
        ] else ...[
          const SizedBox(height: 12),
          const Text(
            'Per aggiungere foto apri l’app come sito.',
            style: TextStyle(fontSize: 12, color: _inkMuted),
          ),
        ],
      ],
    ),
  );
}

// ------------------------------------------------------------------- foto

/// La foto di un capo, oppure un segnaposto con l'emoji dello strato.
class _PieceImage extends StatelessWidget {
  const _PieceImage({this.piece, required this.slot});
  final OutfitPiece? piece;
  final OutfitSlot slot;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xFFF3EEE8),
      alignment: Alignment.center,
      child: Text(slot.emoji, style: const TextStyle(fontSize: 24)),
    );
    final piece = this.piece;
    if (piece == null) return placeholder;
    if (piece.bytes != null) {
      return Image.memory(piece.bytes!, fit: BoxFit.cover);
    }
    if (piece.url == null) return placeholder;
    return Image.network(
      piece.url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

/// Un capo come «foto appoggiata»: bordo bianco, ombra e l'emoji dello strato.
class _Tile extends StatelessWidget {
  const _Tile({required this.piece, this.badge = true, this.radius = 14});
  final OutfitPiece piece;
  final bool badge;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A5A3A20),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    padding: const EdgeInsets.all(3),
    child: Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(radius - 3),
          child: _PieceImage(piece: piece, slot: piece.slot),
        ),
        if (badge)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Text(
                piece.slot.emoji,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
      ],
    ),
  );
}

/// L'outfit composto come su un letto: testa, busto (giubbino e maglia),
/// gambe, poi scarpe e accessori. Gli strati vuoti non occupano spazio.
class _Composition extends StatelessWidget {
  const _Composition({required this.outfit, this.scale = 1});
  final Outfit outfit;
  final double scale;

  /// Altezza approssimativa della composizione, per disporre le schede.
  static double estimate(Outfit outfit) {
    bool has(OutfitSlot s) => outfit.of(s).isNotEmpty;
    final rows = [
      if (has(OutfitSlot.head)) 58.0,
      if (has(OutfitSlot.outer) || has(OutfitSlot.top)) 128.0,
      if (has(OutfitSlot.bottom)) 118.0,
      if (has(OutfitSlot.shoes) || has(OutfitSlot.accessory)) 64.0,
    ];
    if (rows.isEmpty) return 144;
    return rows.reduce((a, b) => a + b) + 8 * (rows.length - 1) + 24;
  }

  @override
  Widget build(BuildContext context) {
    List<OutfitPiece> of(OutfitSlot s) => outfit.of(s).toList();
    final head = of(OutfitSlot.head), outer = of(OutfitSlot.outer);
    final top = of(OutfitSlot.top), bottom = of(OutfitSlot.bottom);
    final shoes = of(OutfitSlot.shoes), extra = of(OutfitSlot.accessory);
    Widget row(List<OutfitPiece> pieces, double height, {double? tileWidth}) =>
        SizedBox(
          height: height * scale,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < pieces.length; i++) ...[
                if (i > 0) SizedBox(width: 8 * scale),
                if (tileWidth == null)
                  Expanded(child: _Tile(piece: pieces[i]))
                else
                  SizedBox(
                    width: tileWidth * scale,
                    child: _Tile(piece: pieces[i], radius: 12),
                  ),
              ],
            ],
          ),
        );
    final upper = [...outer, ...top];
    final small = [...shoes, ...extra];
    final rows = <Widget>[
      if (head.isNotEmpty) row(head, 58, tileWidth: 58),
      if (upper.isNotEmpty) row(upper, 128),
      if (bottom.isNotEmpty) row(bottom, 118),
      if (small.isNotEmpty) row(small, 64, tileWidth: 64),
    ];
    return Container(
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _seasonGradient(outfit.seasons),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: 8 * scale),
            rows[i],
          ],
          if (rows.isEmpty)
            SizedBox(
              height: 120 * scale,
              child: const Center(
                child: Text('👕', style: TextStyle(fontSize: 36)),
              ),
            ),
        ],
      ),
    );
  }
}

class _OutfitCard extends StatefulWidget {
  const _OutfitCard({required this.outfit, required this.onTap});
  final Outfit outfit;
  final VoidCallback onTap;
  @override
  State<_OutfitCard> createState() => _OutfitCardState();
}

class _OutfitCardState extends State<_OutfitCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final outfit = widget.outfit;
    final tags = [...outfit.seasons, ...outfit.styles];
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: _hover ? 1.015 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0x225A3A20),
                blurRadius: _hover ? 22 : 10,
                offset: Offset(0, _hover ? 10 : 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Composition(outfit: outfit),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                outfit.name.isEmpty ? 'Outfit' : outfit.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                            ),
                            Text(
                              '${outfit.pieces.length} capi',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: _inkMuted,
                              ),
                            ),
                          ],
                        ),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: [
                              for (final t in tags)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _tagColor(t).withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${outfitTagEmoji[t] ?? ''} $t',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _tagColor(t),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- armadio

class _Closet extends StatelessWidget {
  const _Closet({
    required this.garments,
    required this.onOpen,
    required this.onCreate,
  });
  final List<Garment> garments;
  final ValueChanged<Garment> onOpen;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    if (garments.isEmpty) {
      return _Empty(hasOutfits: false, onCreate: onCreate);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accentSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            '♻️ Ogni capo è salvato una volta sola: quando crei un outfit scegli «Dall’armadio» e non serve un’altra foto.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF8A3B2A)),
          ),
        ),
        for (final slot in OutfitSlot.values)
          if (garments.where((g) => g.slot == slot).toList() case final list
              when list.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              '${slot.emoji}  ${slot.label}  ·  ${list.length}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final g in list)
                  _GarmentTile(garment: g, onTap: () => onOpen(g)),
              ],
            ),
          ],
      ],
    );
  }
}

class _GarmentTile extends StatelessWidget {
  const _GarmentTile({
    required this.garment,
    required this.onTap,
    this.selected = false,
    this.disabled = false,
    this.size = 118,
  });
  final Garment garment;
  final VoidCallback? onTap;
  final bool selected, disabled;
  final double size;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: disabled ? .45 : 1,
    child: InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: size,
              height: size * 1.2,
              padding: EdgeInsets.all(selected ? 3 : 0),
              decoration: BoxDecoration(
                color: selected ? _accent : Colors.transparent,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Tile(piece: garment.piece(garment.slot), badge: false),
                  if (selected || disabled)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: disabled ? _inkMuted : _accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              disabled
                  ? 'già nell’outfit'
                  : 'in ${garment.outfits.length} outfit',
              style: const TextStyle(fontSize: 11, color: _inkMuted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GarmentDialog extends StatelessWidget {
  const _GarmentDialog({required this.garment});
  final Garment garment;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _cream,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${garment.slot.emoji} ${garment.slot.label}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: .85,
              child: _Tile(piece: garment.piece(garment.slot), badge: false),
            ),
            const SizedBox(height: 12),
            Text(
              'Usato in ${garment.outfits.length} outfit: ${garment.outfits.map((o) => o.name.isEmpty ? 'senza nome' : o.name).join(', ')}',
              style: const TextStyle(fontSize: 12.5, color: _inkMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.auto_awesome, size: 17),
              label: const Text('Crea un outfit con questo'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Chiudi'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Sceglie dall'armadio uno o più capi da mettere in uno strato.
class _GarmentPicker extends StatefulWidget {
  const _GarmentPicker({
    required this.garments,
    required this.slot,
    required this.used,
  });
  final List<Garment> garments;
  final OutfitSlot slot;
  final Set<String> used;
  @override
  State<_GarmentPicker> createState() => _GarmentPickerState();
}

class _GarmentPickerState extends State<_GarmentPicker> {
  late OutfitSlot? _filter = widget.garments.any((g) => g.slot == widget.slot)
      ? widget.slot
      : null;
  final _chosen = <String>{};

  @override
  Widget build(BuildContext context) {
    final list = [
      for (final g in widget.garments)
        if (_filter == null || g.slot == _filter) g,
    ];
    return Dialog(
      backgroundColor: _cream,
      insetPadding: usesPhoneLayout(context)
          ? const EdgeInsets.all(10)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Dall’armadio → ${widget.slot.emoji} ${widget.slot.label}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tocca i capi da aggiungere: usano la foto già salvata.',
                style: TextStyle(fontSize: 12.5, color: _inkMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoicePill(
                    label: 'Tutti',
                    selected: _filter == null,
                    color: _accent,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final s in OutfitSlot.values)
                    if (widget.garments.any((g) => g.slot == s))
                      ChoicePill(
                        label: '${s.emoji} ${s.label}',
                        selected: _filter == s,
                        color: _accent,
                        onTap: () => setState(() => _filter = s),
                      ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final g in list)
                        _GarmentTile(
                          garment: g,
                          size: 104,
                          disabled: widget.used.contains(g.path),
                          selected: _chosen.contains(g.path),
                          onTap: () => setState(
                            () => _chosen.contains(g.path)
                                ? _chosen.remove(g.path)
                                : _chosen.add(g.path),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: _inkMuted),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _chosen.isEmpty
                        ? null
                        : () => Navigator.pop(context, [
                            for (final g in widget.garments)
                              if (_chosen.contains(g.path)) g,
                          ]),
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    child: Text(
                      _chosen.isEmpty
                          ? 'Aggiungi'
                          : 'Aggiungi ${_chosen.length}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ scegli per me

class _SurpriseDialog extends StatefulWidget {
  const _SurpriseDialog({required this.outfits});
  final List<Outfit> outfits;
  @override
  State<_SurpriseDialog> createState() => _SurpriseDialogState();
}

class _SurpriseDialogState extends State<_SurpriseDialog> {
  final _random = math.Random();
  late int _index = _random.nextInt(widget.outfits.length);

  void _next() {
    if (widget.outfits.length < 2) return;
    var i = _index;
    while (i == _index) {
      i = _random.nextInt(widget.outfits.length);
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final outfit = widget.outfits[_index];
    return Dialog(
      backgroundColor: _cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '🎲 Oggi ti metti…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween(begin: .92, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: ClipRRect(
                  key: ValueKey(outfit.id),
                  borderRadius: BorderRadius.circular(20),
                  child: _Composition(outfit: outfit, scale: 1.1),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                outfit.name.isEmpty ? 'Outfit' : outfit.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.outfits.length > 1 ? _next : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('🎲 Un altro'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Perfetto ✓'),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, outfit),
                child: const Text('Modifica questo outfit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- editor

/// Crea o modifica un outfit: capi per ogni strato (foto nuove o
/// dall'armadio), nome, stagioni e stili.
class _OutfitDialog extends StatefulWidget {
  const _OutfitDialog({
    required this.repository,
    required this.draft,
    required this.garments,
    this.original,
  });
  final WardrobeRepository repository;
  final Outfit draft;
  final List<Garment> garments;
  final Outfit? original;
  @override
  State<_OutfitDialog> createState() => _OutfitDialogState();
}

class _OutfitDialogState extends State<_OutfitDialog> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _pieces = [...widget.draft.pieces];
  late final _seasons = {...widget.draft.seasons};
  late final _styles = {...widget.draft.styles};

  /// Strati mostrati: quelli principali più quelli già usati.
  late final _open = {
    OutfitSlot.outer,
    OutfitSlot.top,
    OutfitSlot.bottom,
    OutfitSlot.shoes,
    for (final p in widget.draft.pieces) p.slot,
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _photo(OutfitSlot slot) async {
    // Un capo singolo non ha bisogno di foto enormi: meno spazio occupato.
    final image = await pickImage(maxSide: 1000);
    if (image == null || !mounted) return;
    setState(() => _pieces.add(OutfitPiece(slot: slot, bytes: image.bytes)));
  }

  Future<void> _fromCloset(OutfitSlot slot) async {
    final chosen = await showDialog<List<Garment>>(
      context: context,
      builder: (_) => _GarmentPicker(
        garments: widget.garments,
        slot: slot,
        used: {for (final p in _pieces) ?p.path},
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _pieces.addAll([for (final g in chosen) g.piece(slot)]));
  }

  void _move(OutfitPiece piece, OutfitSlot slot) => setState(() {
    final i = _pieces.indexOf(piece);
    if (i < 0) return;
    _pieces[i] = OutfitPiece(
      slot: slot,
      path: piece.path,
      url: piece.url,
      bytes: piece.bytes,
    );
    _open.add(slot);
  });

  Future<void> _save() async {
    if (_pieces.isEmpty) {
      setState(() => _error = 'Aggiungi almeno un capo.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        Outfit(
          id: widget.draft.id,
          name: _name.text,
          seasons: _seasons,
          styles: _styles,
          // Ordine fisso: dalla testa ai piedi.
          pieces: [
            for (final slot in OutfitSlot.values)
              ..._pieces.where((p) => p.slot == slot),
          ],
        ),
        previous: widget.original,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Salvataggio non riuscito. Controlla la connessione e riprova.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final original = widget.original;
    if (original == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare questo outfit?'),
        content: const Text(
          'Le foto usate solo da questo outfit vengono cancellate; i capi usati anche altrove restano nell’armadio. Non si può annullare.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.repository.delete(original);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Eliminazione non riuscita.';
        });
      }
    }
  }

  Widget _addButton(String emoji, String label, VoidCallback? onTap) => InkWell(
    onTap: _saving ? null : onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      width: 92,
      height: 112,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0C9BC), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _accent,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _slot(OutfitSlot slot) {
    final pieces = _pieces.where((p) => p.slot == slot).toList();
    final closet = widget.garments.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pieces.isEmpty
            ? Colors.white.withValues(alpha: .6)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(slot.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                slot.label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pieces.isEmpty
                      ? slot.hint
                      : '${pieces.length} ${pieces.length == 1 ? 'capo' : 'capi'} · puoi aggiungerne altri',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: _inkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final piece in pieces)
                SizedBox(
                  width: 92,
                  height: 112,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Tile(piece: piece, badge: false, radius: 14),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: _RoundIcon(
                          icon: Icons.close,
                          tooltip: 'Togli',
                          onTap: _saving
                              ? null
                              : () => setState(() => _pieces.remove(piece)),
                        ),
                      ),
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: PopupMenuButton<OutfitSlot>(
                          tooltip: 'Sposta in un altro strato',
                          enabled: !_saving,
                          onSelected: (s) => _move(piece, s),
                          itemBuilder: (_) => [
                            for (final s in OutfitSlot.values)
                              if (s != slot)
                                PopupMenuItem(
                                  value: s,
                                  child: Text('${s.emoji}  ${s.label}'),
                                ),
                          ],
                          child: const _RoundIcon(icon: Icons.swap_vert),
                        ),
                      ),
                    ],
                  ),
                ),
              if (canPickImages)
                _addButton(
                  '📷',
                  pieces.isEmpty ? 'Nuova foto' : 'Un’altra foto',
                  () => _photo(slot),
                ),
              if (closet)
                _addButton('🗂️', 'Dall’armadio', () => _fromCloset(slot)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tags(String title, List<String> values, Set<String> selected) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: _inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in values)
                _TagPill(
                  tag: value,
                  selected: selected.contains(value),
                  onTap: () => setState(
                    () => selected.contains(value)
                        ? selected.remove(value)
                        : selected.add(value),
                  ),
                ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final hidden = [
      for (final s in OutfitSlot.values)
        if (!_open.contains(s)) s,
    ];
    return Dialog(
      backgroundColor: _cream,
      insetPadding: usesPhoneLayout(context)
          ? const EdgeInsets.all(10)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.original == null
                          ? '✨ Nuovo outfit'
                          : '✨ Il tuo outfit',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chiudi',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      maxLength: 60,
                      decoration: InputDecoration(
                        hintText: 'Nome (facoltativo), es. Cena fuori',
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _line),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final slot in OutfitSlot.values)
                      if (_open.contains(slot)) ...[
                        _slot(slot),
                        const SizedBox(height: 10),
                      ],
                    if (hidden.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in hidden)
                            ActionChip(
                              avatar: Text(s.emoji),
                              label: Text('Aggiungi ${s.label.toLowerCase()}'),
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: _line),
                              onPressed: () => setState(() => _open.add(s)),
                            ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    _tags('Stagione', outfitSeasons, _seasons),
                    const SizedBox(height: 12),
                    _tags('Stile', outfitStyles, _styles),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
              child: Row(
                children: [
                  if (widget.original != null)
                    TextButton(
                      onPressed: _saving ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      child: const Text('Elimina'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _saving
                          ? 'Salvataggio…'
                          : 'Salva outfit · ${_pieces.length} capi',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 14, color: Colors.white),
    );
    if (onTap == null) return body;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: body,
      ),
    );
  }
}
