import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'payments_provider.dart';
import 'payment_form.dart';

class PaymentsPage extends ConsumerWidget {
  const PaymentsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pays = ref.watch(paymentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(context: context, builder: (_) => const PaymentFormDialog()),
        child: const Icon(Icons.add),
      ),
      body: pays.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => ListTile(
            title: Text('${list[i].partyName} - Rs ${list[i].total.toStringAsFixed(2)}'),
            subtitle: Text('${list[i].date.year}/${list[i].date.month}/${list[i].date.day} | ${list[i].method ?? ''}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Void payment (soft delete)',
              onPressed: () async {
                await Supabase.instance.client.from('payments').update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', list[i].id);
                ref.invalidate(paymentsProvider);
              },
            ),
          ),
        ),
      ),
    );
  }
}
