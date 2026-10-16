import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton.dart';
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
        loading: () => const SkeletonList(itemCount: 5),
        error: (e, _) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(transactionsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long,
              title: 'No income/expenses yet',
              subtitle:
                  'Record your first transaction to see cashflow and budgets.',
              ctaLabel: 'Add transaction',
              onCta: () {
                ref.invalidate(accountsProvider);
                ref.invalidate(categoriesProvider);
                showDialog(
                    context: context,
                    builder: (_) => const TransactionFormDialog());
              },
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
                  await AuditLog.write(
                      table: 'transactions',
                      rowId: t.id,
                      action: 'archive');
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
