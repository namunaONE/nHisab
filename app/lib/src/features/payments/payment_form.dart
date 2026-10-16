import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import '../../core/cache/connectivity_provider.dart';
import '../../core/cache/outbox.dart';
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
    _validateAmount();
    if (amountError != null) return;

    final amt = double.tryParse(amount.text.trim());
    if (loanId == null || amt == null || amt <= 0) { setState(() => error = 'Select loan + valid amount'); return; }
    setState(() { busy = true; error = null; });
    try {
      final loans = ref.read(loansProvider).valueOrNull ?? [];
      final loan = loans.firstWhere((l) => l.id == loanId!);
      final annual = LoanCalculator.annualRate(rate: loan.rate, rateType: loan.rateType);
      final per = LoanCalculator.perDay(principal: loan.principal, annualRateDecimal: annual, dayBase: loan.dayBase);
      double prev;
      try {
        prev = await prevInterestPaid(loanId!);
      } catch (_) {
        // Offline: approximate with 0; FIFO flush order keeps this consistent.
        prev = 0;
      }
      final split = LoanCalculator.splitPayment(payment: amt, perDayAmount: per, start: loan.startDate, payDate: payDate, prevInterestPaid: prev);
      final day = payDate.toIso8601String().substring(0, 10);
      final payData = {
        'loan_id': loanId,
        'payment_date': day,
        'total_amount': amt,
        'interest_amount': split.interestPart,
        'principal_amount': split.principalPart,
        'payment_method': method,
      };
      final isReceivable = loan.direction == 'receivable';
      final txnLegs = <Map<String, dynamic>>[];
      if (accountId != null) {
        if (split.interestPart > 0) {
          txnLegs.add({
            'account_id': accountId,
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
          txnLegs.add({
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
      }
      // Offline first: queue payment + legs, sync on reconnect.
      if (ref.read(isOfflineProvider)) {
        await Outbox.enqueue(table: 'payments', data: payData);
        for (final leg in txnLegs) {
          await Outbox.enqueue(table: 'transactions', data: leg);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Offline — payment queued, will sync on reconnect.'),
          ));
          Navigator.pop(context, true);
        }
        return;
      }
      final payRow = await Supabase.instance.client
          .from('payments')
          .insert(payData)
          .select('id')
          .single();
      await AuditLog.write(
          table: 'payments',
          rowId: (payRow['id'] ?? '').toString(),
          action: 'insert',
          newData: payData);
      // Wallets-first link: mirror payment legs as transactions when a
      // wallet is picked. Interest leg categorized via lookup, principal leg
      // stays uncategorized (excluded from income/expense by loan_id rule).
      // Missing budget tables (pre-migration) are ignored on purpose.
      if (accountId != null) {
        try {
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
          for (final leg in txnLegs) {
            final payload = Map<String, dynamic>.from(leg);
            if (payload['notes']?.toString().contains('interest') == true) {
              payload['category_id'] = intCatId;
            }
            await Supabase.instance.client
                .from('transactions')
                .insert(payload);
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
            const SizedBox(height: 12),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Amount Rs *', errorText: amountError), onChanged: (_) => updatePreview()),
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
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Please wait...' : 'Save')),
      ],
    );
  }
}
