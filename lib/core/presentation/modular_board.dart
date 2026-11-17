import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../app/theme.dart';
import 'responsive_layout.dart';
import '../storage/key_value_store.dart';
import '../storage/key_value_store_factory.dart';
import '../i18n/i18n.dart';
import '../i18n/names.dart';

class BoardModule {
  const BoardModule(
    this.id,
    this.title,
    this.child, {
    this.columns = 12,
    this.height = 300,
    this.minHeight = 160,
    this.scroll = true,
    this.mobileHeight,
  });
  final String id, title;
  final Widget child;
  final int columns;
  final double height, minHeight;
  final bool scroll;
  final double? mobileHeight;
}

class ModularBoard extends StatefulWidget {
  const ModularBoard({
    required this.area,
    required this.modules,
    this.scope = 'local',
    this.store,
    super.key,
  });
  final String area, scope;
  final List<BoardModule> modules;
  final KeyValueStore? store;
  @override
  State<ModularBoard> createState() => ModularBoardState();
}

/// Absolute coordinates after editing. The grid is only an initial preset;
/// gestures never snap or constrain movement to columns. Colliding neighbours
/// move down while the edited rectangle stays at the chosen coordinates.
class ModularBoardState extends State<ModularBoard> {
  late final KeyValueStore _store = widget.store ?? createKeyValueStore();
  String get _key => 'dashboard.layout.v1.${widget.scope}.${widget.area}';
  final _geometry = _BoardGeometry();
  final Map<String, GlobalKey> _anchors = {};
  List<String> _order = [];
  final Map<String, int> _legacyWidths = {};
  final Map<String, double> _legacyHeights = {};
  bool _editing = false, _saving = false, _free = false;
  String? _error;
  bool _ready = false;
  bool _repairOverlaps = false;

  /// Larghezza a cui si riferiscono le coordinate salvate: su uno schermo
  /// diverso le schede vengono riproporzionate in orizzontale.
  double? _layoutWidth;
  static const _minLayoutWidth = 900.0;
  Map<String, Rect>? _gestureRects;
  int _loadVersion = 0;
  Future<void> _writes = Future<void>.value();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ModularBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area != widget.area || oldWidget.scope != widget.scope) {
      _ready = false;
      _free = false;
      _editing = false;
      _geometry.rects.clear();
      _layoutWidth = null;
      _gestureRects = null;
      _order = [];
      _legacyWidths.clear();
      _legacyHeights.clear();
      _load();
    }
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    try {
      final raw = await _store.read(_key);
      if (!mounted || version != _loadVersion || raw == null) return;
      final data = jsonDecode(raw) as Map;
      final restored = <String, Rect>{};
      _order = List<String>.from(data['order'] ?? []);
      for (final e in ((data['widths'] as Map?) ?? {}).entries) {
        _legacyWidths[e.key as String] = (e.value as num).toInt().clamp(3, 12);
      }
      for (final e in ((data['heights'] as Map?) ?? {}).entries) {
        final value = (e.value as num).toDouble();
        if (value.isFinite) _legacyHeights[e.key as String] = value;
      }
      for (final e in ((data['rects'] as Map?) ?? {}).entries) {
        final v = (e.value as List)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList();
        if (v.length == 4 &&
            v.every((n) => n.isFinite) &&
            v[0] >= 0 &&
            v[1] >= 0 &&
            v[2] > 0 &&
            v[3] > 0) {
          restored[e.key as String] = Rect.fromLTWH(v[0], v[1], v[2], v[3]);
        }
      }
      _geometry.rects.addAll(restored);
      final savedWidth = (data['width'] as num?)?.toDouble();
      _layoutWidth = savedWidth != null && savedWidth.isFinite && savedWidth > 0
          ? savedWidth
          : restored.isEmpty
          ? null
          : restored.values.fold<double>(0, (v, r) => math.max(v, r.right));
      _free = restored.isNotEmpty;
      _repairOverlaps = _free;
    } catch (_) {
      if (mounted && version == _loadVersion) {
        _error = tr(
          'Layout salvato non leggibile; disposizione predefinita.',
          'Saved layout couldn’t be read; using the default one.',
        );
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _ready = true);
    }
  }

  Future<void> _persist() {
    final key = _key;
    final value = jsonEncode({
      'version': 2,
      'order': _order,
      if (_layoutWidth != null) 'width': _layoutWidth,
      'rects': {
        for (final e in _geometry.rects.entries)
          e.key: [e.value.left, e.value.top, e.value.width, e.value.height],
      },
    });
    // Serialize snapshots so a slower earlier write cannot replace a later edit.
    return _writes = _writes
        .catchError((Object _) {})
        .then((_) => _store.write(key, value));
  }

  void _finishGesture() {
    _gestureRects = null;
    _geometry.end();
    if (!_ready) return;
    unawaited(
      _persist().catchError((Object _) {
        if (mounted) {
          setState(
            () => _error = tr(
              'Layout non salvato. Premi Salva layout per riprovare.',
              'Layout not saved. Press Save layout to try again.',
            ),
          );
        }
      }),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _persist();
      if (mounted)
        setState(() {
          _editing = false;
          _free = true;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error = tr(
            'Layout non salvato. Riprova.',
            'Layout not saved. Try again.',
          ),
        );
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _reset() async {
    try {
      await _writes.catchError((Object _) {});
      await _store.remove(_key);
      if (mounted)
        setState(() {
          _free = false;
          _order = [];
          _legacyWidths.clear();
          _legacyHeights.clear();
          _geometry.rects.clear();
          _layoutWidth = null;
          _geometry.active = null;
          _error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error = tr('Ripristino non riuscito.', 'Reset failed.'),
        );
    }
  }

  /// Riproporziona in orizzontale la disposizione salvata alla larghezza
  /// disponibile, così le schede riempiono anche uno schermo più grande.
  void _fitWidth(double available) {
    if (_geometry.active != null) return;
    final from = _layoutWidth;
    _layoutWidth = available;
    if (from == null || from <= 0 || (from - available).abs() < .5) return;
    final k = available / from;
    for (final e in _geometry.rects.entries.toList()) {
      final r = e.value;
      _geometry.rects[e.key] = Rect.fromLTWH(
        r.left * k,
        r.top,
        r.width * k,
        r.height,
      );
    }
  }

  void showSection(String id) {
    final context = _anchors[id]?.currentContext;
    if (context != null)
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 180),
        alignment: .03,
      );
  }

  void _begin(String id) {
    _free = true;
    _gestureRects = Map.of(_geometry.rects);
    _geometry.begin(id);
  }

  void _move(
    String id,
    Offset delta, {
    bool resize = false,
    double minHeight = 160,
  }) {
    final r = _geometry.rects[id]!;
    final next = resize
        ? Rect.fromLTWH(
            r.left,
            r.top,
            math.max(160, r.width + delta.dx),
            math.max(minHeight, r.height + delta.dy),
          )
        : Rect.fromLTWH(
            math.max(0, r.left + delta.dx),
            math.max(0, r.top + delta.dy),
            r.width,
            r.height,
          );
    if (_gestureRects != null) {
      for (final e in _gestureRects!.entries) {
        if (e.key != id) _geometry.rects[e.key] = e.value;
      }
    }
    _geometry.rects[id] = next;
    _geometry.resolveOverlaps(preferred: id);
    _geometry.update(id, next);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready)
      return SizedBox(
        height: 48,
        child: Center(
          child: Text(
            tr('Ripristino layout…', 'Resetting layout…'),
            style: TextStyle(fontSize: 12),
          ),
        ),
      );
    final byId = {for (final m in widget.modules) m.id: m};
    if (_free &&
        byId.keys.any(
          (id) =>
              !_geometry.visible.contains(id) &&
              _geometry.rects.containsKey(id),
        )) {
      _repairOverlaps = true;
    }
    // Keep saved geometry for modules temporarily absent during data loading.
    _geometry.visible = byId.keys.toSet();
    final modules = [
      for (final id in {..._order, ...byId.keys})
        if (byId[id] != null) byId[id]!,
    ];
    if (usesPhoneLayout(context)) {
      // Ignore desktop coordinates on a phone; never write this presentation
      // back to the user's saved desktop layout.
      return Column(
        key: const ValueKey('phone-board'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in modules)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                key: _anchors.putIfAbsent(m.id, () => GlobalKey()),
                child: m.mobileHeight == null
                    ? m.child
                    : SizedBox(
                        height:
                            m.mobileHeight! *
                            math.max(
                              1,
                              MediaQuery.textScalerOf(context).scale(1),
                            ),
                        child: m.child,
                      ),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (_editing)
              Expanded(
                child: Text(
                  tr(
                    'Posizione libera · salvataggio automatico · guide senza snap',
                    'Free positioning · saved automatically · guides without snapping',
                  ),
                  style: TextStyle(color: AppColors.green, fontSize: 12),
                ),
              )
            else
              const Spacer(),
            if (_editing)
              TextButton(
                onPressed: _saving ? null : _reset,
                child: Text(tr('Ripristina layout', 'Reset layout')),
              ),
            TextButton.icon(
              onPressed: _saving
                  ? null
                  : () {
                      if (_editing) {
                        _save();
                      } else {
                        setState(() => _editing = true);
                      }
                    },
              icon: Icon(
                _editing ? Icons.check : Icons.dashboard_customize_outlined,
                size: 17,
              ),
              label: Text(
                _editing
                    ? tr('Salva layout', 'Save layout')
                    : tr('Modifica layout', 'Edit layout'),
              ),
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        LayoutBuilder(
          builder: (context, box) {
            if (!_free) {
              _layoutWidth = box.maxWidth;
              // Preserve the existing default and migrate previously saved presets.
              final bottoms = List<double>.filled(12, 0);
              final unit = (box.maxWidth + 12) / 12;
              for (final m in modules) {
                final span = box.maxWidth < 720
                    ? 12
                    : (_legacyWidths[m.id] ?? m.columns);
                var left = 0, top = double.infinity;
                for (var col = 0; col <= 12 - span; col++) {
                  var y = 0.0;
                  for (var i = col; i < col + span; i++) {
                    y = math.max(y, bottoms[i]);
                  }
                  if (y < top) {
                    top = y;
                    left = col;
                  }
                }
                final height = math.max(
                  m.minHeight,
                  _legacyHeights[m.id] ?? m.height,
                );
                _geometry.rects[m.id] = Rect.fromLTWH(
                  left * unit,
                  top,
                  span * unit - 12,
                  height,
                );
                for (var i = left; i < left + span; i++) {
                  bottoms[i] = top + height + 12;
                }
              }
            } else {
              _fitWidth(math.max(box.maxWidth, _minLayoutWidth));
              // Only newly appearing modules receive a default location.
              for (final m in modules) {
                _geometry.rects.putIfAbsent(
                  m.id,
                  () => Rect.fromLTWH(
                    0,
                    _geometry.height,
                    box.maxWidth,
                    m.height,
                  ),
                );
              }
              if (_repairOverlaps) {
                _repairOverlaps = false;
                if (_geometry.resolveOverlaps()) {
                  // Repair only invalid saved overlaps, once; normal restore and
                  // window resizing preserve the saved coordinates exactly.
                  scheduleMicrotask(() {
                    if (mounted) _finishGesture();
                  });
                }
              }
            }
            final stack = Stack(
              clipBehavior: Clip.none,
              children: [
                for (final m in modules)
                  AnimatedBuilder(
                    key: ValueKey('module-${m.id}'),
                    animation: _geometry,
                    child: RepaintBoundary(child: _panel(m)),
                    builder: (context, child) => Positioned.fromRect(
                      key: ValueKey('position-${m.id}'),
                      rect: _geometry.rects[m.id]!,
                      child: child!,
                    ),
                  ),
                if (_editing)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _GuidePainter(_geometry)),
                    ),
                  ),
              ],
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: AnimatedBuilder(
                animation: _geometry,
                child: stack,
                builder: (context, child) => SizedBox(
                  width: math.max(box.maxWidth, _geometry.width),
                  height: _geometry.height + (_editing ? 100 : 0),
                  child: child,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _panel(BoardModule m) => Container(
    key: _anchors.putIfAbsent(m.id, () => GlobalKey()),
    child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _editing,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, box) {
                  final content = BoardExtent(
                    height: box.maxHeight,
                    originalHeight: m.height,
                    child: m.child,
                  );
                  return m.scroll
                      ? SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: box.maxHeight,
                            ),
                            child: content,
                          ),
                        )
                      : content;
                },
              ),
            ),
          ),
        ),
        if (_editing) ...[
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.green.withValues(alpha: .55),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 30,
            child: GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              key: ValueKey('drag-${m.id}'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => _begin(m.id),
              onPanUpdate: (d) => _move(m.id, d.delta),
              onPanEnd: (_) => _finishGesture(),
              onPanCancel: _finishGesture,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.greenSoft.withValues(alpha: .95),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.drag_indicator, size: 18),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          sectionLabel(m.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              key: ValueKey('resize-${m.id}'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => _begin(m.id),
              onPanUpdate: (d) =>
                  _move(m.id, d.delta, resize: true, minHeight: m.minHeight),
              onPanEnd: (_) => _finishGesture(),
              onPanCancel: _finishGesture,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpLeftDownRight,
                child: Container(
                  color: AppColors.greenSoft,
                  padding: const EdgeInsets.all(6),
                  child: const Icon(
                    Icons.open_in_full,
                    size: 18,
                    color: AppColors.green,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _BoardGeometry extends ChangeNotifier {
  final rects = <String, Rect>{};
  Set<String> visible = {};
  Iterable<Rect> get visibleRects =>
      visible.map((id) => rects[id]).whereType<Rect>();
  String? active;
  bool resolveOverlaps({String? preferred}) {
    final ids = visible.where(rects.containsKey).toList()
      ..sort((a, b) {
        if (a == b) return 0;
        if (a == preferred) return -1;
        if (b == preferred) return 1;
        final byTop = rects[a]!.top.compareTo(rects[b]!.top);
        return byTop != 0 ? byTop : rects[a]!.left.compareTo(rects[b]!.left);
      });
    final placed = <Rect>[];
    var changed = false;
    for (final id in ids) {
      var rect = rects[id]!;
      while (true) {
        final collisions = placed
            .where((other) => other.overlaps(rect))
            .toList();
        if (collisions.isEmpty) break;
        final top = collisions.fold(
          rect.top,
          (double y, r) => math.max(y, r.bottom + 12),
        );
        rect = Rect.fromLTWH(rect.left, top, rect.width, rect.height);
      }
      if (rect != rects[id]) {
        rects[id] = rect;
        changed = true;
      }
      placed.add(rect);
    }
    return changed;
  }

  double get width => visibleRects.fold(0.0, (v, r) => math.max(v, r.right));
  double get height =>
      visibleRects.fold(0.0, (v, r) => math.max(v, r.bottom + 12));
  void begin(String id) {
    active = id;
    notifyListeners();
  }

  void update(String id, Rect value) {
    rects[id] = value;
    notifyListeners();
  }

  void end() {
    active = null;
    notifyListeners();
  }
}

/// A paint-only proximity indicator; it never changes any rectangle.
class _GuidePainter extends CustomPainter {
  _GuidePainter(this.geometry) : super(repaint: geometry);
  final _BoardGeometry geometry;
  @override
  void paint(Canvas canvas, Size size) {
    final r = geometry.rects[geometry.active];
    if (r == null) return;
    final paint = Paint()
      ..color = AppColors.green.withValues(alpha: .8)
      ..strokeWidth = 1;
    for (final e in geometry.rects.entries) {
      if (e.key == geometry.active || !geometry.visible.contains(e.key))
        continue;
      final other = e.value;
      for (final x in [r.left, r.center.dx, r.right]) {
        for (final target in [other.left, other.center.dx, other.right]) {
          if ((x - target).abs() <= 4)
            canvas.drawLine(
              Offset(target, math.min(r.top, other.top)),
              Offset(target, math.max(r.bottom, other.bottom)),
              paint,
            );
        }
      }
      for (final y in [r.top, r.center.dy, r.bottom]) {
        for (final target in [other.top, other.center.dy, other.bottom]) {
          if ((y - target).abs() <= 4)
            canvas.drawLine(
              Offset(math.min(r.left, other.left), target),
              Offset(math.max(r.right, other.right), target),
              paint,
            );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) =>
      oldDelegate.geometry != geometry;
}

class BoardExtent extends InheritedWidget {
  const BoardExtent({
    required this.height,
    required this.originalHeight,
    required super.child,
    super.key,
  });
  final double height, originalHeight;
  static BoardExtent? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BoardExtent>();
  @override
  bool updateShouldNotify(BoardExtent oldWidget) => oldWidget.height != height;
}
