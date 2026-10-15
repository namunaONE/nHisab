import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../accounts/accounts_provider.dart';
import '../categories/categories_provider.dart';
import '../categories/category_form.dart';
import 'transaction_form.dart';
import 'transactions_provider.dart';

class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(transactionsProvider);
    final fmt = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Add category',
            onPressed: () => showDialog(
                context: context,
                builder: (_) => const CategoryFormDialog()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addTxn',
        tooltip: 'Add transaction',
        onPressed: () {
          ref.invalidate(accountsProvider);
          ref.invalidate(categoriesProvider);
          showDialog(
              context: context,
              builder: (_) => const TransactionFormDialog());
        },
        child: const Icon(Icons.add),
      ),
      body: txnsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Supabase error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No income/expenses yet. Tap + to record one.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final t = list[i];
              final isIncome = t.kind == 'income';
              final isTransfer = t.kind == 'transfer';
              return Dismissible(
                key: ValueKey(t.id),
                direction: DismissDirection.endToStart,
                background: Container(
                    color: scheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.archive_outlined)),
                confirmDismiss: (_) async => await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Archive transaction?'),
                        content: const Text(
                            'Archived rows stay in audit but leave balances.'),
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
                    ) ??
                    false,
                onDismissed: (_) async {
                  await Supabase.instance.client
                      .from('transactions')
                      .update({
                    'deleted_at': DateTime.now().toIso8601String()
                  }).eq('id', t.id);
                  ref.invalidate(transactionsProvider);
                  ref.invalidate(accountsProvider);
                },
                child: ListTile(
                  leading: Icon(
                    isTransfer
                        ? Icons.swap_horiz
                        : isIncome
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                    color: isTransfer
                        ? scheme.tertiary
                        : isIncome
                            ? scheme.secondary
                            : scheme.error,
                  ),
                  title: Text(t.categoryName ?? t.kind),
                  subtitle: Text(
                      '${t.accountName} • ${t.date.year}/${t.date.month}/${t.date.day}'),
                  trailing: Text(
                    isTransfer
                        ? fmt.format(t.amount)
                        : '${isIncome ? '+' : '-'}${fmt.format(t.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isTransfer
                          ? scheme.onSurface
                          : isIncome
                              ? scheme.secondary
                              : scheme.error,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
