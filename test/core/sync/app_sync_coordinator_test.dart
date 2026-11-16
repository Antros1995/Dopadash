import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/core/sync/app_sync_coordinator.dart';

void main() {
  testWidgets(
    'returning after hours and browser event bursts restore auth before data',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final events = StreamController<void>();
      var sessions = 0, reads = 0;
      final order = <String>[];
      final sync = AppSyncCoordinator(
        recoveryEvents: events.stream,
        ensureSession: () async {
          sessions++;
          order.add('auth');
        },
        synchronize: () async {
          order.add('data');
          reads++;
        },
      )..start();
      addTearDown(sync.dispose);
      addTearDown(() {
        unawaited(events.close());
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(hours: 4));
      expect(reads, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      events.add(null);
      events.add(null);
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 401));
      await tester.pump();
      expect(sessions, 1);
      expect(reads, 1);
      expect(order, ['auth', 'data']);
      await tester.pump(const Duration(minutes: 1));
      expect(reads, 2);
      sync.dispose();
      unawaited(events.close());
    },
  );

  testWidgets(
    'a failed token refresh retries after connectivity recovers without restarting',
    (tester) async {
      var sessions = 0, reads = 0;
      final sync = AppSyncCoordinator(
        ensureSession: () async {
          if (++sessions == 1) throw StateError('offline');
        },
        synchronize: () async {
          reads++;
        },
      )..start();
      addTearDown(sync.dispose);
      await sync.refresh();
      expect(reads, 0);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(reads, 1);
      expect(sessions, 2);
      sync.dispose();
    },
  );

  testWidgets('concurrent requests coalesce and disposal stops late reads', (
    tester,
  ) async {
    var sessions = 0, reads = 0;
    final pending = Completer<void>();
    final sync = AppSyncCoordinator(
      ensureSession: () {
        sessions++;
        return sessions == 1 ? pending.future : Future.value();
      },
      synchronize: () async {
        reads++;
      },
    )..start();
    final first = sync.refresh();
    final second = sync.refresh();
    expect(sessions, 1);
    pending.complete();
    await Future.wait([first, second]);
    expect(sessions, 2);
    expect(reads, 2);
    sync.dispose();
    await tester.pump(const Duration(hours: 1));
    expect(reads, 2);
  });

  testWidgets(
    'a stalled session check expires and a later retry can synchronize',
    (tester) async {
      final stalled = Completer<void>();
      var attempts = 0, reads = 0;
      final sync = AppSyncCoordinator(
        ensureSession: () => ++attempts == 1 ? stalled.future : Future.value(),
        synchronize: () async {
          reads++;
        },
      )..start();
      addTearDown(sync.dispose);
      final first = sync.refresh();
      await tester.pump(const Duration(seconds: 31));
      await first;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(reads, 1);
      stalled.complete();
      sync.dispose();
    },
  );
}
