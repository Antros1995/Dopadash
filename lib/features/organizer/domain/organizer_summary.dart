import 'dart:convert';

/// Perché una cosa compare nel riepilogo della Home.
enum OrganizerReason { focus, due, nudge, next }

class OrganizerItem {
  const OrganizerItem({
    required this.id,
    required this.title,
    required this.project,
    required this.emoji,
    required this.color,
    required this.reason,
    this.due = '',
    this.who = '',
    this.waitingDays = 0,
    this.late = false,
  });
  final String id, title, project, emoji, due, who;

  /// Colore del progetto, 0xAARRGGBB.
  final int color;
  final OrganizerReason reason;
  final int waitingDays;
  final bool late;
}

/// Una data importante di un progetto, ancora da raggiungere.
class OrganizerMilestone {
  const OrganizerMilestone({
    required this.id,
    required this.title,
    required this.project,
    required this.color,
    required this.due,
    required this.daysLeft,
  });
  final String id, title, project, due;
  final int color;

  /// Giorni mancanti: 0 oggi, negativo se la data è passata.
  final int daysLeft;
}

/// Visione d'insieme delle caselle aperte nell'Organizzatore.
///
/// Le attività non sono salvate a parte: come nella pagina dell'Organizzatore,
/// si leggono dalle caselle scritte dentro il testo dei fogli.
class OrganizerSummary {
  const OrganizerSummary({
    this.focus = 0,
    this.mine = 0,
    this.waiting = 0,
    this.due = 0,
    this.open = 0,
    this.items = const [],
    this.milestones = const [],
  });

  /// Nel focus di oggi.
  final int focus;

  /// Tocca a me: senza attesa, oppure da sollecitare.
  final int mine;

  /// In attesa di qualcuno.
  final int waiting;

  /// Scadute o in scadenza oggi.
  final int due;
  final int open;
  final List<OrganizerItem> items;

  /// Milestone aperte con una data, dalla più vicina.
  final List<OrganizerMilestone> milestones;

  static const followDays = 3;

  static OrganizerSummary fromJson(String? raw, DateTime now) {
    if (raw == null || raw.isEmpty) return const OrganizerSummary();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const OrganizerSummary();
    }
    return decoded is Map ? fromData(decoded, now) : const OrganizerSummary();
  }

  static OrganizerSummary fromData(Map<dynamic, dynamic> data, DateTime now) {
    final today = _ymd(now);
    final projects = data['projects'];
    if (projects is! List) return const OrganizerSummary();
    final open = <_Task>[];
    final next = <_Task>[];
    final miles = <_Task>[];
    for (final project in projects) {
      if (project is! Map || project['archived'] == true) continue;
      final name = '${project['name'] ?? ''}';
      final emoji = '${project['emoji'] ?? ''}';
      final color = _color(project['color']);
      var hasNext = project['id'] == 'inbox';
      final sheets = project['sheets'];
      if (sheets is! List) continue;
      for (final sheet in sheets) {
        if (sheet is! Map) continue;
        for (final task in _tasks('${sheet['html'] ?? ''}')) {
          if (task.done) continue;
          task
            ..project = name
            ..emoji = emoji
            ..color = color;
          if (task.milestone) {
            if (task.due.isNotEmpty) miles.add(task);
            continue;
          }
          open.add(task);
          if (!hasNext && task.who.isEmpty) {
            hasNext = true;
            next.add(task);
          }
        }
      }
    }
    bool nudge(_Task t) {
      if (t.who.isEmpty) return false;
      final since = t.nudge.isNotEmpty ? t.nudge : t.ws;
      final from = _parse(since);
      if (from == null) return false;
      return !_parse(today)!.isBefore(from.add(const Duration(days: followDays)));
    }

    final seen = <String>{};
    final items = <OrganizerItem>[];
    void add(_Task t, OrganizerReason reason) {
      if (!seen.add(t.id.isEmpty ? '${t.project}|${t.title}' : t.id)) return;
      final since = _parse(t.ws);
      items.add(
        OrganizerItem(
          id: t.id,
          title: t.title,
          project: t.project,
          emoji: t.emoji,
          color: t.color,
          reason: reason,
          due: t.due,
          who: t.who,
          waitingDays: since == null
              ? 0
              : _parse(today)!.difference(since).inDays.clamp(0, 9999),
          late: t.due.isNotEmpty && t.due.compareTo(today) < 0,
        ),
      );
    }

    final focus = open.where((t) => t.focus == today).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final due =
        open.where((t) => t.due.isNotEmpty && t.due.compareTo(today) <= 0).toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    for (final t in focus) {
      add(t, OrganizerReason.focus);
    }
    for (final t in due) {
      add(t, OrganizerReason.due);
    }
    for (final t in open.where(nudge)) {
      add(t, OrganizerReason.nudge);
    }
    for (final t in next) {
      add(t, OrganizerReason.next);
    }
    return OrganizerSummary(
      focus: focus.length,
      mine: open.where((t) => t.who.isEmpty || nudge(t)).length,
      waiting: open.where((t) => t.who.isNotEmpty).length,
      due: due.length,
      open: open.length,
      items: items,
      milestones: [
        for (final t in miles..sort((a, b) => a.due.compareTo(b.due)))
          if (_parse(t.due) case final date?)
            OrganizerMilestone(
              id: t.id,
              title: t.title,
              project: t.project,
              color: t.color,
              due: t.due,
              daysLeft: date.difference(_parse(today)!).inDays,
            ),
      ],
    );
  }

  static final _row = RegExp(
    r'<div\b([^>]*)>([\s\S]*?)</div>',
    caseSensitive: false,
  );
  static final _attribute = RegExp(r'([\w-]+)="([^"]*)"');
  static final _tag = RegExp(r'<[^>]*>');
  static final _space = RegExp(r'\s+');
  static final _entity = RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);');

  static Iterable<_Task> _tasks(String html) sync* {
    // Rientro della casella madre corrente: le caselle più rientrate sotto di
    // lei sono sotto-attività e si vedono solo aprendola nell'Organizzatore.
    var parentIndent = -1;
    for (final row in _row.allMatches(html)) {
      final attributes = {
        for (final a in _attribute.allMatches(row[1]!)) a[1]!: _text(a[2]!),
      };
      final indent = int.tryParse(attributes['data-i'] ?? '') ?? 0;
      if (!(attributes['class'] ?? '').split(' ').contains('todo')) {
        if (indent <= parentIndent) parentIndent = -1;
        continue;
      }
      final title = _text(row[2]!.replaceAll(_tag, ''));
      if (title.isEmpty) continue;
      if (parentIndent >= 0 && indent > parentIndent) continue;
      parentIndent = indent;
      yield _Task(
        id: attributes['data-id'] ?? '',
        title: title,
        done: (attributes['data-done'] ?? '').isNotEmpty,
        milestone: (attributes['data-ms'] ?? '').isNotEmpty,
        due: attributes['data-due'] ?? '',
        who: attributes['data-who'] ?? '',
        ws: attributes['data-ws'] ?? '',
        nudge: attributes['data-nudge'] ?? '',
        focus: attributes['data-focus'] ?? '',
        order: int.tryParse(attributes['data-fo'] ?? '') ?? 0,
      );
    }
  }

  static String _text(String value) => value
      .replaceAllMapped(_entity, (m) {
        final name = m[1]!;
        if (name.startsWith('#')) {
          final code = name[1] == 'x' || name[1] == 'X'
              ? int.tryParse(name.substring(2), radix: 16)
              : int.tryParse(name.substring(1));
          return code == null ? m[0]! : String.fromCharCode(code);
        }
        return const {
              'amp': '&',
              'lt': '<',
              'gt': '>',
              'quot': '"',
              'apos': "'",
              'nbsp': ' ',
            }[name] ??
            m[0]!;
      })
      .replaceAll(_space, ' ')
      .trim();

  static int _color(Object? value) {
    final hex = '${value ?? ''}'.replaceFirst('#', '');
    final parsed = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    return 0xFF000000 | (parsed ?? 0x6E6E73);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parse(String ymd) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(ymd);
    return m == null
        ? null
        : DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
}

class _Task {
  _Task({
    required this.id,
    required this.title,
    required this.done,
    required this.milestone,
    required this.due,
    required this.who,
    required this.ws,
    required this.nudge,
    required this.focus,
    required this.order,
  });
  final String id, title, due, who, ws, nudge, focus;
  final bool done, milestone;
  final int order;
  String project = '', emoji = '';
  int color = 0xFF6E6E73;
}
