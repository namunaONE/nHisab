import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import '../../core/cache/connectivity_provider.dart';
import '../../core/calculator/loan_calculator.dart';
import '../../core/dates/bs_date.dart';
import '../../core/dates/bs_picker.dart';
import '../../core/ids.dart';
import '../accounts/accounts_provider.dart';
import '../loans/loan_model.dart';
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
    if (loans == null || loans.isEmpty || loanId == null || amt <= 0) {
      if (mounted) setState(() => preview = '');
      return;
    }
    final loan = loans.firstWhere(
      (l) => l.id == loanId,
      orElse: () => loans.first,
    );
    final annual =
        LoanCalculator.annualRate(rate: loan.rate, rateType: loan.rateType);
    final per = LoanCalculator.perDay(
        principal: loan.principal,
        annualRateDecimal: annual,
        dayBase: loan.dayBase);
    double prev;
    try {
      prev = await prevInterestPaid(loanId!);
    } catch (_) {
      if (mounted) {
        setState(() =>
            preview = 'Connect to preview the interest/principal allocation.');
      }
      return;
    }
    if (!mounted) return;
    final split = LoanCalculator.splitPayment(
      payment: amt,
      perDayAmount: per,
      start: loan.startDate,
      payDate: payDate,
      prevInterestPaid: prev,
      principal: loan.principal,
      prevPrincipalPaid: loan.principalPaid,
    );
    final over = split.excess > 0.005
        ? ' • overpayment ${split.excess.toStringAsFixed(2)}'
        : '';
    setState(() => preview =
        'Interest ${split.interestPart.toStringAsFixed(2)} + Principal ${split.principalPart.toStringAsFixed(2)} (prior interest paid ${prev.toStringAsFixed(2)})$over');
  }

  Future<void> save() async {
    _validateAmount();
    if (amountError != null) return;

    final amt = double.tryParse(amount.text.trim());
    if (loanId == null || amt == null || amt <= 0) {
      setState(() => error = 'Select loan + valid amount');
      return;
    }
    final loans = ref.read(loansProvider).valueOrNull ?? [];
    LoanRow? loan;
    for (final l in loans) {
      if (l.id == loanId) {
        loan = l;
        break;
      }
    }
    if (loan == null) {
      setState(() => error = 'Select a loan first');
      return;
    }
    final today = DateTime.now();
    if (payDate.isAfter(DateTime(today.year, today.month, today.day))) {
      setState(() => error = 'Payment date cannot be in the future');
      return;
    }
    if (payDate.isBefore(DateTime(
        loan.startDate.year, loan.startDate.month, loan.startDate.day))) {
      setState(
          () => error = 'Payment date cannot be before the loan start date');
      return;
    }
    // Offline allocation needs prior interest/principal paid. Guessing zero
    // caused wrong splits, so money writes now require a connection.
    if (ref.read(isOfflineProvider)) {
      setState(() => error =
          'Recording a payment requires a connection so interest and principal are allocated atomically. Reconnect and try again.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });
    try {
      final day = payDate.toIso8601String().substring(0, 10);
      final clientId = newUuidV4();

      // Prefer the server RPC: it locks the loan, allocates interest first and
      // writes the payment, wallet legs and audit row in one transaction. The
      // client-side split is only computed for the pre-migration fallback.
      final usedRpc = await _recordViaRpc(
        amount: amt,
        day: day,
        clientId: clientId,
      );
      if (!usedRpc) {
        final annual =
            LoanCalculator.annualRate(rate: loan.rate, rateType: loan.rateType);
        final per = LoanCalculator.perDay(
            principal: loan.principal,
            annualRateDecimal: annual,
            dayBase: loan.dayBase);
        final prev = await prevInterestPaid(loanId!);
        final split = LoanCalculator.splitPayment(
          payment: amt,
          perDayAmount: per,
          start: loan.startDate,
          payDate: payDate,
          prevInterestPaid: prev,
          principal: loan.principal,
          prevPrincipalPaid: loan.principalPaid,
        );
        if (split.excess > 0.005) {
          setState(() => error =
              'Payment exceeds the unpaid principal by Rs ${split.excess.toStringAsFixed(2)}. Reduce the amount.');
          return;
        }
        await _recordLegacy(
          loan: loan,
          amount: amt,
          day: day,
          split: split,
        );
      }
      ref.invalidate(paymentsProvider);
      ref.invalidate(loansProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(transactionsProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Server-authoritative path. Falls back only when the function has not
  /// been deployed yet (expand/contract migration); validation errors are
  /// surfaced instead of being retried as a legacy write.
  Future<bool> _recordViaRpc({
    required double amount,
    required String day,
    required String clientId,
  }) async {
    try {
      await Supabase.instance.client.rpc('record_payment', params: {
        'p_loan_id': loanId,
        'p_amount': amount,
        'p_payment_date': day,
        'p_payment_method': method,
        'p_remarks': null,
        'p_account_id': accountId,
        'p_client_id': clientId,
      });
      return true;
    } on PostgrestException catch (e) {
      final missing = e.code == 'PGRST202' ||
          e.code == '42883' ||
          e.message.toLowerCase().contains('could not find the function');
      if (missing) return false;
      rethrow;
    }
  }

  /// Temporary non-atomic bridge for projects that have not applied the
  /// payment RPC migration yet. The RPC path above is the supported path once
  /// the migration is applied.
  Future<void> _recordLegacy({
    required LoanRow loan,
    required double amount,
    required String day,
    required ({double interestPart, double principalPart, double excess}) split,
  }) async {
    final payData = {
      'loan_id': loan.id,
      'payment_date': day,
      'total_amount': amount,
      'interest_amount': split.interestPart,
      'principal_amount': split.principalPart,
      'payment_method': method,
    };
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
    if (accountId == null) return;
    final isReceivable = loan.direction == 'receivable';
    String? intCatId;
    try {
      final cats = await Supabase.instance.client
          .from('categories')
          .select('id, kind, name')
          .filter('deleted_at', 'is', null);
      for (final c in (cats as List)) {
        final n = (c['name'] ?? '').toString().toLowerCase();
        if (c['kind'] == (isReceivable ? 'income' : 'expense') &&
            n.contains('interest')) {
          intCatId = (c['id'] ?? '').toString();
          break;
        }
      }
    } catch (_) {}
    final legs = <Map<String, dynamic>>[];
    if (split.interestPart > 0) {
      final interestLeg = <String, dynamic>{
        'account_id': accountId,
        'loan_id': loan.id,
        'kind': isReceivable ? 'income' : 'expense',
        'amount': split.interestPart,
        'txn_date': day,
        'notes': isReceivable ? 'loan interest received' : 'loan interest paid',
      };
      if (intCatId != null) interestLeg['category_id'] = intCatId;
      legs.add(interestLeg);
    }
    if (split.principalPart > 0) {
      legs.add({
        'account_id': accountId,
        'loan_id': loan.id,
        'kind': isReceivable ? 'income' : 'expense',
        'amount': split.principalPart,
        'txn_date': day,
        'excluded_from_cashflow': true,
        'notes':
            isReceivable ? 'loan principal received' : 'loan principal paid',
      });
    }
    for (final leg in legs) {
      await Supabase.instance.client.from('transactions').insert(leg);
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
                items: list
                    .map((l) => DropdownMenuItem(
                        value: l.id,
                        child: Text(
                            '${l.partyName} - ${l.principal.toStringAsFixed(0)}')))
                    .toList(),
                onChanged: (v) {
                  setState(() => loanId = v);
                  updatePreview();
                },
              ),
            ),
            accounts.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Wallets error: $e'),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: accountId,
                hint: const Text('Wallet (links to cashflow)'),
                items: list
                    .map((a) =>
                        DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setState(() => accountId = v),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: 'Amount Rs *', errorText: amountError),
                onChanged: (_) => updatePreview()),
            DropdownButtonFormField<String>(
              initialValue: method,
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(
                    value: 'bank_transfer', child: Text('Bank transfer')),
                DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                DropdownMenuItem(value: 'online', child: Text('Online'))
              ],
              onChanged: (v) => setState(() => method = v!),
            ),
            Row(children: [
              Expanded(child: Text('Date: ${BsDate.dual(payDate)}')),
              TextButton(
                  onPressed: () async {
                    final d = await BsPicker.pick(context,
                        initialDate: payDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100));
                    if (d != null) {
                      setState(() => payDate = d);
                      updatePreview();
                    }
                  },
                  child: const Text('Pick')),
            ]),
            if (preview.isNotEmpty)
              Text(preview, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
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
