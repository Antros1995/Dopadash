import 'dart:async';

import 'package:supabase/supabase.dart';

/// Emits one event whenever one of [tables] changes for the signed-in user.
/// Row Level Security keeps notifications scoped to the active account.
Stream<void> watchSupabaseTables({
  required SupabaseClient client,
  required String channelName,
  required List<String> tables,
}) {
  late final StreamController<void> controller;
  RealtimeChannel? channel;

  controller = StreamController<void>.broadcast(
    onListen: () {
      if (client.auth.currentUser == null) return;
      channel = client.channel(
        '${channelName}_${DateTime.now().microsecondsSinceEpoch}',
      );
      for (final table in tables) {
        channel!.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) {
            if (!controller.isClosed) controller.add(null);
          },
        );
      }
      channel!.subscribe((status, error) {
        // A reconnect must also read changes missed while the socket was down.
        if (status == RealtimeSubscribeStatus.subscribed &&
            !controller.isClosed) {
          controller.add(null);
        }
      });
    },
    onCancel: () async {
      final activeChannel = channel;
      if (activeChannel != null) await client.removeChannel(activeChannel);
    },
  );
  return controller.stream;
}
