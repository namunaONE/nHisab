import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import '../auth/profiles_provider.dart';
import 'payment_form.dart';
import 'payments_provider.dart';

class PaymentsPage extends ConsumerWidget {
  const PaymentsPage({super.key});

  Future<void> _void(BuildContext context, WidgetRef ref, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void payment?'),
        content: const Text(
            'The payment and its wallet entries will be hidden. Nothing is hard-deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Void')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      var usedRpc = true;
      try {
        await Supabase.instance.client
            .rpc('void_payment', params: {'p_payment_id': id});
      } on PostgrestException catch (e) {
        final missing = e.code == 'PGRST202' ||
            e.code == '42883' ||
            e.message.toLowerCase().contains('could not find the function');
        if (!missing) rethrow;
        usedRpc = false;
      }
      if (!usedRpc) {
        await Supabase.instance.client.from('payments').update(
            {'deleted_at': DateTime.now().toIso8601String()}).eq('id', id);
        await AuditLog.write(
            table: 'payments', rowId: id, action: 'archive');
      }
      ref.invalidate(paymentsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Void failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pays = ref.watch(paymentsProvider);
    final canWrite = ref.watch(canWriteProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      floatingActionButton: canWrite
          ? FloatingActionButton(
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const PaymentFormDialog()),
              child: const Icon(Icons.add),
            )
          : null,
      body: pays.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(
                '${list[i].partyName} - Rs ${list[i].total.toStringAsFixed(2)}'),
            subtitle: Text(
                '${list[i].date.year}/${list[i].date.month}/${list[i].date.day} | ${list[i].method ?? ''}'),
            trailing: canWrite
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Void payment (soft delete)',
                    onPressed: () => _void(context, ref, list[i].id),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
