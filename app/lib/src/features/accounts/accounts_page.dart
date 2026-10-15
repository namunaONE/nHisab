import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'account_form.dart';
import 'accounts_provider.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final fmt = NumberFormat('#,##0.00');
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addAccount',
        tooltip: 'Add wallet',
        onPressed: () => showDialog(
            context: context, builder: (_) => const AccountFormDialog()),
        child: const Icon(Icons.add),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Supabase error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No wallets yet. Tap + to add cash / bank / mobile.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final a = list[i];
              return ListTile(
                leading: Icon(
                  a.type == 'bank'
                      ? Icons.account_balance
                      : a.type == 'mobile_wallet'
                          ? Icons.smartphone
                          : Icons.wallet,
                ),
                title: Text(a.name),
                subtitle: Text('${a.type} • open ${fmt.format(a.openingBalance)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(fmt.format(a.computedBalance),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      tooltip: 'Edit wallet',
                      onPressed: () => showDialog(
                          context: context,
                          builder: (_) =>
                              AccountFormDialog(existing: a)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      tooltip: 'Archive wallet',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Archive wallet?'),
                            content: Text(
                                'Archive ${a.name}? History is kept, list hides it.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Archive')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await Supabase.instance.client
                              .from('accounts')
                              .update({
                            'deleted_at':
                                DateTime.now().toIso8601String()
                          }).eq('id', a.id);
                          ref.invalidate(accountsProvider);
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
