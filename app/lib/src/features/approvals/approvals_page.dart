import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'approvals_provider.dart';

class ApprovalsPage extends ConsumerStatefulWidget {
  const ApprovalsPage({super.key});
  @override
  ConsumerState<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends ConsumerState<ApprovalsPage> {
  bool busy = false;

  Future<void> _decide(String id, bool approve) async {
    setState(() => busy = true);
    try {
      await Supabase.instance.client.rpc('decide_approval', params: {
        'p_approval_id': id,
        'p_approve': approve,
        'p_note': null,
      });
      ref.invalidate(approvalsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(approve ? 'Approved.' : 'Rejected.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(approvalsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Approval Inbox')),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No approval requests.'));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              final isPending = r.status == 'pending';
              final isSelf = r.requestedBy ==
                  Supabase.instance.client.auth.currentUser?.id;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text('${r.entityType} • ${r.action}'),
                  subtitle: Text(
                      'Status: ${r.status} • ${r.requestedAt.year}/${r.requestedAt.month}/${r.requestedAt.day}'),
                  trailing: isPending && !isSelf
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: busy ? null : () => _decide(r.id, true),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: busy ? null : () => _decide(r.id, false),
                            ),
                          ],
                        )
                      : Text(r.status),
                ),
              );
            },
          );
        },
      ),
    );
  }
}