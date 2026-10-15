import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../accounts/accounts_provider.dart';
import '../categories/categories_provider.dart';

class TransactionFormDialog extends ConsumerStatefulWidget {
  const TransactionFormDialog({super.key});
  @override
  ConsumerState<TransactionFormDialog> createState() =>
      _TransactionFormDialogState();
}

class _TransactionFormDialogState extends ConsumerState<TransactionFormDialog> {
  String? accountId;
  String? toAccountId;
  String? categoryId;
  String kind = 'expense';
  final amount = TextEditingController();
  DateTime txnDate = DateTime.now();
  final notes = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> save() async {
    final amt = double.tryParse(amount.text.trim());
    if (accountId == null) {
      setState(() => error = 'Select wallet');
      return;
    }
    if (amt == null || amt <= 0) {
      setState(() => error = 'Valid amount required');
      return;
    }
    if (kind != 'transfer' && categoryId == null) {
      setState(() => error = 'Select category');
      return;
    }
    if (kind == 'transfer' &&
        (toAccountId == null || toAccountId == accountId)) {
      setState(() => error = 'Select a different destination wallet');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final client = Supabase.instance.client;
      final day = txnDate.toIso8601String().substring(0, 10);
      if (kind == 'transfer') {
        // Two legs, same amount/date, excluded from income/expense sums.
        await client.from('transactions').insert({
          'account_id': accountId,
          'kind': 'transfer',
          'amount': amt,
          'txn_date': day,
          'notes': notes.text.trim().isEmpty
              ? 'transfer-out'
              : '${notes.text.trim()} (out)',
        });
        await client.from('transactions').insert({
          'account_id': toAccountId,
          'kind': 'transfer',
          'amount': amt,
          'txn_date': day,
          'notes': notes.text.trim().isEmpty
              ? 'transfer-in'
              : '${notes.text.trim()} (in)',
        });
      } else {
        await client.from('transactions').insert({
          'account_id': accountId,
          'category_id': categoryId,
          'kind': kind,
          'amount': amt,
          'txn_date': day,
          'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        });
      }
      ref.invalidate(accountsProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);
    return AlertDialog(
      title: const Text('Add Transaction'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'income', label: Text('Income')),
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                  ButtonSegment(value: 'transfer', label: Text('Transfer')),
                ],
                selected: {kind},
                onSelectionChanged: (s) =>
                    setState(() => kind = s.first),
              ),
              const SizedBox(height: 8),
              accounts.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Wallets error: $e'),
                data: (list) => DropdownButtonFormField<String>(
                  value: accountId,
                  hint: Text(kind == 'transfer'
                      ? 'From wallet *'
                      : 'Wallet *'),
                  items: list
                      .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text('${a.name} (${a.type})')))
                      .toList(),
                  onChanged: (v) => setState(() => accountId = v),
                ),
              ),
              if (kind == 'transfer')
                accounts.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => Text('Wallets error: $e'),
                  data: (list) => DropdownButtonFormField<String>(
                    value: toAccountId,
                    hint: const Text('To wallet *'),
                    items: list
                        .map((a) => DropdownMenuItem(
                            value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setState(() => toAccountId = v),
                  ),
                ),
              if (kind != 'transfer')
                categories.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Categories error: $e'),
                  data: (list) {
                    final filtered =
                        list.where((c) => c.kind == kind).toList();
                    return DropdownButtonFormField<String>(
                      value: categoryId,
                      hint: const Text('Category *'),
                      items: filtered
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setState(() => categoryId = v),
                    );
                  },
                ),
              TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Amount Rs *')),
              Row(children: [
                Text(
                    'Date: ${txnDate.year}/${txnDate.month}/${txnDate.day}'),
                TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: txnDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100));
                      if (d != null) setState(() => txnDate = d);
                    },
                    child: const Text('Pick')),
              ]),
              TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes')),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving...' : 'Save')),
      ],
    );
  }
}
