import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/calculator/loan_calculator.dart';
import '../accounts/accounts_provider.dart';
import '../loans/loans_provider.dart';
import '../transactions/transactions_provider.dart';
import 'payments_provider.dart';

class PaymentFormDialog extends ConsumerStatefulWidget {
  const PaymentFormDialog({super.key});
  @override
  ConsumerState<PaymentFormDialog> createState() => _PaymentFormDialogState();
}

class _PaymentFormDialogState extends ConsumerState<PaymentFormDialog> {
  String? loanId;
  String? accountId;
  DateTime payDate = DateTime.now();
  final amount = TextEditingController();
  String method = 'cash';
  bool busy = false;
  String? error;
  String preview = '';

  Future<double> prevInterestPaid(String loanId) async {
    final rows = await Supabase.instance.client
        .from('payments')
        .select('interest_amount')
        .eq('loan_id', loanId)
        .filter('deleted_at', 'is', null);
    double s = 0;
    for (final r in (rows as List)) {
      s += ((r['interest_amount'] as num?) ?? 0).toDouble();
    }
    return s;
  }

  Future<void> updatePreview() async {
    final loans = ref.read(loansProvider).valueOrNull;
    final amt = double.tryParse(amount.text) ?? 0;
    if (loans == null || loanId == null || amt <= 0) { if (mounted) setState(() => preview = ''); return; }
    final loan = loans.firstWhere((l) => l.id == loanId!, orElse: () => loans.first);
    final annual = LoanCalculator.annualRate(rate: loan.rate, rateType: loan.rateType);
    final per = LoanCalculator.perDay(principal: loan.principal, annualRateDecimal: annual, dayBase: loan.dayBase);
    final prev = await prevInterestPaid(loanId!);
    if (!mounted) return;
    final split = LoanCalculator.splitPayment(payment: amt, perDayAmount: per, start: loan.startDate, payDate: payDate, prevInterestPaid: prev);
    setState(() => preview = 'Interest ${split.interestPart.toStringAsFixed(2)} + Principal ${split.principalPart.toStringAsFixed(2)} (prior interest paid ${prev.toStringAsFixed(2)})');
  }

  Future<void> save() async {
    final amt = double.tryParse(amount.text.trim());
    if (loanId == null || amt == null || amt <= 0) { setState(() => error = 'Select loan + valid amount'); return; }
    setState(() { busy = true; error = null; });
    try {
      final loans = ref.read(loansProvider).valueOrNull ?? [];
      final loan = loans.firstWhere((l) => l.id == loanId!);
      final annual = LoanCalculator.annualRate(rate: loan.rate, rateType: loan.rateType);
      final per = LoanCalculator.perDay(principal: loan.principal, annualRateDecimal: annual, dayBase: loan.dayBase);
      final prev = await prevInterestPaid(loanId!);
      final split = LoanCalculator.splitPayment(payment: amt, perDayAmount: per, start: loan.startDate, payDate: payDate, prevInterestPaid: prev);
      await Supabase.instance.client.from('payments').insert({
        'loan_id': loanId,
        'payment_date': payDate.toIso8601String().substring(0, 10),
        'total_amount': amt,
        'interest_amount': split.interestPart,
        'principal_amount': split.principalPart,
        'payment_method': method,
      });
      // Wallets-first link: mirror payment legs as transactions when a
      // wallet is picked. Interest leg categorized via lookup, principal leg
      // stays uncategorized (excluded from income/expense by loan_id rule).
      // Missing budget tables (pre-migration) are ignored on purpose.
      if (accountId != null) {
        try {
          final day = payDate.toIso8601String().substring(0, 10);
          final isReceivable = loan.direction == 'receivable';
          String? intCatId;
          try {
            final cats = await Supabase.instance.client
                .from('categories')
                .select('id, kind, name')
                .filter('deleted_at', 'is', null);
            for (final c in (cats as List)) {
              final n = (c['name'] ?? '').toString().toLowerCase();
              if (isReceivable &&
                  c['kind'] == 'income' &&
                  n.contains('interest')) {
                intCatId = (c['id'] ?? '').toString();
                break;
              }
              if (!isReceivable &&
                  c['kind'] == 'expense' &&
                  n.contains('interest')) {
                intCatId = (c['id'] ?? '').toString();
                break;
              }
            }
          } catch (_) {}
          if (split.interestPart > 0) {
            await Supabase.instance.client.from('transactions').insert({
              'account_id': accountId,
              'category_id': intCatId,
              'loan_id': loanId,
              'kind': isReceivable ? 'income' : 'expense',
              'amount': split.interestPart,
              'txn_date': day,
              'notes': isReceivable
                  ? 'loan interest received'
                  : 'loan interest paid',
            });
          }
          if (split.principalPart > 0) {
            await Supabase.instance.client.from('transactions').insert({
              'account_id': accountId,
              'loan_id': loanId,
              'kind': isReceivable ? 'income' : 'expense',
              'amount': split.principalPart,
              'txn_date': day,
              'notes': isReceivable
                  ? 'loan principal received'
                  : 'loan principal paid',
            });
          }
          ref.invalidate(accountsProvider);
          ref.invalidate(transactionsProvider);
        } catch (_) {}
      }
      ref.invalidate(paymentsProvider);
      ref.invalidate(loansProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(loansProvider);
    final accounts = ref.watch(accountsProvider);
    return AlertDialog(
      title: const Text('Record Payment'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            loans.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Loans error: $e'),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: loanId,
                hint: const Text('Loan *'),
                items: list.map((l) => DropdownMenuItem(value: l.id, child: Text('${l.partyName} - ${l.principal.toStringAsFixed(0)}'))).toList(),
                onChanged: (v) { setState(() => loanId = v); updatePreview(); },
              ),
            ),
            accounts.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Wallets error: $e'),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: accountId,
                hint: const Text('Wallet (links to cashflow)'),
                items: list.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                onChanged: (v) => setState(() => accountId = v),
              ),
            ),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount Rs *'), onChanged: (_) => updatePreview()),
            DropdownButtonFormField<String>(
              initialValue: method,
              items: const [DropdownMenuItem(value: 'cash', child: Text('Cash')), DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')), DropdownMenuItem(value: 'cheque', child: Text('Cheque')), DropdownMenuItem(value: 'online', child: Text('Online'))],
              onChanged: (v) => setState(() => method = v!),
            ),
            Row(children: [
              Text('Date: ${payDate.year}/${payDate.month}/${payDate.day}'),
              TextButton(onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: payDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) { setState(() => payDate = d); updatePreview(); }
              }, child: const Text('Pick')),
            ]),
            if (preview.isNotEmpty) Text(preview, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Saving...' : 'Save')),
      ],
    );
  }
}
