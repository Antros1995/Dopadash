import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/organizer/application/organizer_controller.dart';
import 'package:monitoraggio_personale_desktop/features/organizer/data/organizer_local_store.dart';
import 'package:monitoraggio_personale_desktop/features/organizer/data/organizer_remote.dart';
import 'package:monitoraggio_personale_desktop/features/organizer/domain/organizer_summary.dart';

String data(String html, {String? savedAt, bool archived = false}) =>
    jsonEncode({
      'savedAt': ?savedAt,
      'projects': [
        {
          'id': 'inbox',
          'name': 'Inbox',
          'emoji': '📥',
          'color': '#7a7690',
          'sheets': [
            {'id': 'inbox', 'html': '<div><br></div>'},
          ],
        },
        {
          'id': 'p1',
          'name': 'Report',
          'emoji': '📊',
          'color': '#5856d6',
          'archived': archived,
          'sheets': [
            {'id': 's1', 'html': html},
          ],
        },
      ],
    });

Map<String, dynamic> copy(Object value) =>
    jsonDecode(value is String ? value : jsonEncode(value))
        as Map<String, dynamic>;

class FakeRemote implements OrganizerRemote {
  Map<String, dynamic>? row;
  int saves = 0;
  bool fail = false;
  final events = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<Map<String, dynamic>?> fetch() async {
    if (fail) throw StateError('offline');
    return row == null ? null : copy(row!);
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    saves++;
    row = copy(data);
  }
}

void main() {
  final now = DateTime(2026, 11, 12, 10);
  const html =
      '<div class="h1">Chiusura</div>'
      '<div class="todo" data-id="a" data-due="2026-11-10">Chiudere i dati di <mark>ottobre</mark> &amp; inviare</div>'
      '<div data-i="1">nota</div>'
      '<div class="todo" data-id="b" data-who="Lucia" data-ws="2026-11-08">Ricevere i numeri da Lucia</div>'
      '<div class="todo" data-id="c" data-who="Mario" data-ws="2026-11-11">Aspettare Mario</div>'
      '<div class="todo" data-id="d" data-focus="2026-11-12" data-fo="1">Preparare le slide</div>'
      '<div class="todo" data-id="e" data-done="2026-11-11T09:00:00.000Z">Fatta</div>'
      '<div class="todo" data-id="f">   </div>'
      '<div class="todo" data-id="m1" data-ms="1" data-due="2026-11-25">Consegna al cliente</div>'
      '<div class="todo" data-id="m2" data-ms="1" data-due="2026-11-11">Avvio</div>'
      '<div class="todo" data-id="m3" data-ms="1" data-due="2026-11-01" data-done="2026-11-01T09:00:00.000Z">Raggiunta</div>'
      '<div class="todo" data-id="m4" data-ms="1">Senza data</div>';
  const one = '<div class="todo" data-id="x">Uno</div>';

  test('il riepilogo legge le caselle dal testo dei fogli', () {
    final s = OrganizerSummary.fromJson(data(html), now);
    expect(s.open, 4);
    expect(s.focus, 1);
    expect(s.waiting, 2);
    expect(s.due, 1);
    // a e d senza attesa, b da sollecitare dopo tre giorni.
    expect(s.mine, 3);
    expect(s.items.map((i) => i.id), ['d', 'a', 'b']);
    expect(s.items[1].title, 'Chiudere i dati di ottobre & inviare');
    expect(s.items[1].late, isTrue);
    expect(s.items[2].reason, OrganizerReason.nudge);
    expect(s.items[2].waitingDays, 4);
    expect(s.items.first.color, 0xFF5856D6);
    // Le milestone hanno un elenco proprio e non contano tra le cose da fare.
    expect(s.milestones.map((m) => m.id), ['m2', 'm1']);
    expect(s.milestones.map((m) => m.daysLeft), [-1, 13]);
  });

  test('progetti archiviati e dati illeggibili non contano', () {
    expect(OrganizerSummary.fromJson(data(html, archived: true), now).open, 0);
    expect(OrganizerSummary.fromJson('{rotto', now).open, 0);
    expect(OrganizerSummary.fromJson(null, now).items, isEmpty);
  });

  test('il prossimo passo di un progetto compare se non ci sono urgenze', () {
    final s = OrganizerSummary.fromJson(
      data('$one<div class="todo" data-id="y">Due</div>'),
      now,
    );
    expect(s.items.single.id, 'x');
    expect(s.items.single.reason, OrganizerReason.next);
  });

  group('sincronizzazione', () {
    late MemoryOrganizerLocalStore store;
    late FakeRemote remote;
    OrganizerController controller() => OrganizerController(
      store: store,
      remote: remote,
      now: () => now,
      pushDelay: Duration.zero,
    );

    setUp(() {
      store = MemoryOrganizerLocalStore();
      remote = FakeRemote();
    });

    test('la prima volta carica i dati locali e li marca', () async {
      store.value = data(html);
      final c = controller()..start();
      await c.synchronize();
      expect(remote.saves, 1);
      expect(remote.row!['savedAt'], isNotNull);
      expect(copy(store.value!)['savedAt'], remote.row!['savedAt']);
      expect(c.synced, isTrue);
      await c.synchronize();
      expect(remote.saves, 1);
      c.dispose();
    });

    test('un dispositivo vuoto riceve la copia condivisa', () async {
      remote.row = copy(data(html, savedAt: '2026-11-12T08:00:00.000Z'));
      final c = controller()..start();
      await c.synchronize();
      expect(c.summary.open, 4);
      expect(remote.saves, 0);
      c.dispose();
    });

    test('vince la copia salvata per ultima, in entrambe le direzioni', () async {
      remote.row = copy(data(html, savedAt: '2026-11-12T08:00:00.000Z'));
      store.value = data(one, savedAt: '2026-11-12T09:00:00.000Z');
      final c = controller()..start();
      await c.synchronize();
      expect(remote.saves, 1);
      expect(remote.row!['savedAt'], '2026-11-12T09:00:00.000Z');
      remote.row = copy(data(html, savedAt: '2026-11-12T09:30:00.000Z'));
      await c.synchronize();
      expect(c.summary.open, 4);
      expect(remote.saves, 1);
      c.dispose();
    });

    test('appunti locali mai sincronizzati vanno nella copia di riserva', () async {
      remote.row = copy(data(html, savedAt: '2026-11-12T08:00:00.000Z'));
      store.value = data(one);
      final c = controller()..start();
      await c.synchronize();
      expect(store.saved, data(one));
      expect(c.summary.open, 4);
      c.dispose();
    });

    test('un salvataggio della pagina viene inviato; offline resta locale', () async {
      final c = controller()..start();
      remote.fail = true;
      await c.synchronize();
      expect(c.synced, isFalse);
      remote.fail = false;
      store.edit(data(html, savedAt: '2026-11-12T09:00:00.000Z'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.summary.open, 4);
      expect(remote.saves, 1);
      expect(c.synced, isTrue);
      c.dispose();
    });
  });
}
