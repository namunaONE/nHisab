import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_model.dart';

/// Latest 100 notifications for this tenant, newest first.
/// RLS scopes rows to `current_tenant_id()` automatically.
final notificationsProvider = FutureProvider<List<NotificationRow>>((ref) async {
  final res = await Supabase.instance.client
      .from('notification_queue')
      .select(
          'id, loan_id, alert_type, channel, status, scheduled_at, sent_at, created_at, loans(parties(name))')
      .order('created_at', ascending: false)
      .limit(100);
  return (res as List).map((r) => NotificationRow.fromMap(r)).toList();
});

/// Unread (pending) notification count for the bell badge.
final unreadNotificationsProvider = FutureProvider<int>((ref) async {
  final list = await ref.watch(notificationsProvider.future);
  return list.where((n) => n.isUnread).length;
});

/// Subscribes to Realtime `postgres_changes` on `notification_queue` and
/// invalidates [notificationsProvider] on every insert/update.
/// Call once per app lifetime (e.g. from HomeShell initState).
RealtimeChannel subscribeNotifications(WidgetRef ref) {
  final client = Supabase.instance.client;
  final channel = client.channel('public:notification_queue');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notification_queue',
        callback: (_) {
          ref.invalidate(notificationsProvider);
        },
      )
      .subscribe();
  return channel;
}
