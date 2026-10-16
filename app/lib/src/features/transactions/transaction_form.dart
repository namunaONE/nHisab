import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import '../../core/cache/connectivity_provider.dart';
import '../../core/cache/outbox.dart';
import '../../core/dates/bs_date.dart';
import '../../core/dates/bs_picker.dart';
import '../accounts/accounts_provider.dart';
import '../categories/categories_provider.dart';
import 'transactions_provider.dart';

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
  // Per-field inline validation state
  String? amountError;

  @override
  void initState() {
    super.initState();
    amount.addListener(_validateAmount);
  }

  @override
  void dispose() {
    amount.removeListener(_validateAmount);
    amount.dispose();
    notes.dispose();
    super.dispose();
  }

  void _validateAmount() {
    final a = double.tryParse(amount.text.trim());
    if (amount.text.trim().isEmpty) {
      setState(() => amountError = null);
    } else if (a == null) {
      setState(() => amountError = 'Enter a number like 5000.00');
    } else if (a <= 0) {
      setState(() => amountError = 'Amount must be greater than 0');
    } else {
      setState(() => amountError = null);
    }
  }

  Future<void> save() async {
    _validateAmount();
    if (amountError != null) return;

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
    final day = txnDate.toIso8601String().substring(0, 10);
    final payloads = <Map<String, dynamic>>[];
    if (kind == 'transfer') {
      // Two legs, same amount/date, excluded from income/expense sums.
      payloads.add({
        'account_id': accountId,
        'kind': 'transfer',
        'amount': amt,
        'txn_date': day,
        'notes': notes.text.trim().isEmpty
            ? 'transfer-out'
            : '${notes.text.trim()} (out)',
      });
      payloads.add({
        'account_id': toAccountId,
        'kind': 'transfer',
        'amount': amt,
        'txn_date': day,
        'notes': notes.text.trim().isEmpty
            ? 'transfer-in'
            : '${notes.text.trim()} (in)',
      });
    } else {
      payloads.add({
        'account_id': accountId,
        'category_id': categoryId,
        'kind': kind,
        'amount': amt,
        'txn_date': day,
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      });
    }
    // Offline first: queue and sync on reconnect (ADR4 write queue).
    if (ref.read(isOfflineProvider)) {
      for (final p in payloads) {
        await Outbox.enqueue(table: 'transactions', data: p);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Offline — queued, will sync on reconnect.'),
        ));
        Navigator.pop(context, true);
      }
      return;
    }
    try {
      final client = Supabase.instance.client;
      for (final p in payloads) {
        final row = await client
            .from('transactions')
            .insert(p)
            .select('id')
            .single();
        await AuditLog.write(
            table: 'transactions',
            rowId: (row['id'] ?? '').toString(),
            action: 'insert',
            newData: p);
      }
      ref.invalidate(accountsProvider);
      ref.invalidate(transactionsProvider);
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
                  initialValue: accountId,
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
                    initialValue: toAccountId,
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
                      initialValue: categoryId,
                      hint: const Text('Category *'),
                      items: filtered
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setState(() => categoryId = v),
                    );
                  },
                ),
              const SizedBox(height: 12),
              TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount Rs *',
                    errorText: amountError,
                  )),
              Row(children: [
                Expanded(
                    child: Text('Date: ${BsDate.dual(txnDate)}')),
                TextButton(
                    onPressed: () async {
                      final d = await BsPicker.pick(
                          context,
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
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Please wait...' : 'Save')),
      ],
    );
  }
}
