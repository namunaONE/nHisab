import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton.dart';
import 'notification_model.dart';
import 'notifications_provider.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await Supabase.instance.client
                  .from('notification_queue')
                  .update({
                    'status': 'sent',
                    'sent_at': DateTime.now().toIso8601String(),
                  })
                  .eq('status', 'pending');
              ref.invalidate(notificationsProvider);
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: notifsAsync.when(
        loading: () => const SkeletonList(itemCount: 6),
        error: (e, _) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: 'No notifications yet',
              subtitle:
                  'Due and overdue loan alerts appear here once the daily '
                  'dispatcher runs (08:00 NPT).',
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final n = list[i];
              return ListTile(
                leading: Icon(
                  _channelIcon(n.channel),
                  color: _statusColor(n.status, scheme),
                ),
                title: Text(
                  _title(n),
                  style: TextStyle(
                    fontWeight:
                        n.isUnread ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  '${_channelLabel(n.channel)} • ${_statusLabel(n.status)}'
                  '${n.partyName != null ? ' • ${n.partyName}' : ''}',
                ),
                trailing: n.isUnread
                    ? IconButton(
                        icon:
                            const Icon(Icons.mark_email_read_outlined, size: 20),
                        tooltip: 'Mark read',
                        onPressed: () async {
                          await Supabase.instance.client
                              .from('notification_queue')
                              .update({
                            'status': 'sent',
                            'sent_at': DateTime.now().toIso8601String(),
                          }).eq('id', n.id);
                          ref.invalidate(notificationsProvider);
                        },
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  IconData _channelIcon(String channel) {
    switch (channel) {
      case 'email':
        return Icons.email_outlined;
      case 'sms':
        return Icons.sms_outlined;
      case 'in_app':
      default:
        return Icons.notifications_outlined;
    }
  }

  String _title(NotificationRow n) {
    switch (n.alertType) {
      case 'due_soon':
        return 'Payment due soon';
      case 'overdue':
        return 'Payment overdue';
      case 'budget_overspent':
        return 'Budget overspent';
      default:
        return n.alertType;
    }
  }

  String _channelLabel(String channel) {
    switch (channel) {
      case 'email':
        return 'Email';
      case 'sms':
        return 'SMS';
      default:
        return 'In-app';
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Unread';
      case 'sent':
        return 'Sent';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'pending':
        return scheme.primary;
      case 'failed':
        return scheme.error;
      default:
        return scheme.onSurfaceVariant;
    }
  }
}
