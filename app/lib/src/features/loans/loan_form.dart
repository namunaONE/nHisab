import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import '../../core/dates/bs_date.dart';
import '../../core/dates/bs_picker.dart';
import '../parties/parties_provider.dart';
import 'loans_provider.dart';

class LoanFormDialog extends ConsumerStatefulWidget {
  final String? loanId;
  const LoanFormDialog({super.key, this.loanId});

  @override
  ConsumerState<LoanFormDialog> createState() => _LoanFormDialogState();
}

class _LoanFormDialogState extends ConsumerState<LoanFormDialog> {
  String? partyId;
  final principal = TextEditingController();
  final ratePct = TextEditingController(text: '18');
  final tenureMonths = TextEditingController(text: '12');
  String rateType = 'annual';
  String method = 'daily_accrual';
  int dayBase = 360;
  String direction = 'receivable';
  String loanType = 'personal';
  DateTime startDate = DateTime.now();
  DateTime? dueDate;
  double tdsPct = 0;
  final remarks = TextEditingController();
  bool busy = false;
  bool loading = false;
  String? error;
  // Per-field inline validation state
  String? partyError;
  String? principalError;
  String? rateError;

  @override
  void initState() {
    super.initState();
    principal.addListener(_validatePrincipal);
    ratePct.addListener(_validateRate);
    if (widget.loanId != null) {
      loading = true;
      _loadLoan();
    }
  }

  Future<void> _loadLoan() async {
    try {
      final row = await Supabase.instance.client
          .from('loans')
          .select('*')
          .eq('id', widget.loanId!)
          .maybeSingle();
      if (row == null) return;
      setState(() {
        partyId = row['party_id']?.toString();
        principal.text = (row['principal_amount'] as num).toString();
        final r = (row['rate'] as num).toDouble();
        ratePct.text = (r * 100).toString();
        rateType = (row['rate_type'] ?? 'annual').toString();
        method = (row['calculation_method'] ?? 'daily_accrual').toString();
        dayBase = (row['day_base'] as num?)?.toInt() ?? 360;
        direction = (row['direction'] ?? 'receivable').toString();
        loanType = (row['loan_type'] ?? 'personal').toString();
        startDate = DateTime.parse(row['start_date'] as String);
        if (row['due_date'] != null) dueDate = DateTime.parse(row['due_date'] as String);
        tdsPct = (row['tds_pct'] as num?)?.toDouble() ?? 0;
        final tn = row['tenure_months'] as num?;
        tenureMonths.text = tn == null ? '12' : tn.toInt().toString();
        remarks.text = (row['remarks'] ?? '').toString();
        loading = false;
      });
    } catch (e) {
      setState(() { error = e.toString(); loading = false; });
    }
  }

  @override
  void dispose() {
    principal.removeListener(_validatePrincipal);
    ratePct.removeListener(_validateRate);
    principal.dispose();
    ratePct.dispose();
    tenureMonths.dispose();
    remarks.dispose();
    super.dispose();
  }

  void _validatePrincipal() {
    final p = double.tryParse(principal.text.trim());
    if (principal.text.trim().isEmpty) {
      setState(() => principalError = null);
    } else if (p == null) {
      setState(() => principalError = 'Enter a number like 1500000.00');
    } else if (p <= 0) {
      setState(() => principalError = 'Principal must be greater than 0');
    } else {
      setState(() => principalError = null);
    }
  }

  void _validateRate() {
    final r = double.tryParse(ratePct.text.trim());
    if (ratePct.text.trim().isEmpty) {
      setState(() => rateError = null);
    } else if (r == null) {
      setState(() => rateError = 'Enter a number like 18');
    } else if (r < 0) {
      setState(() => rateError = 'Rate cannot be negative');
    } else if (r > 24) {
      setState(() => rateError = 'Warning: rate above 24% — verify with bank');
    } else {
      setState(() => rateError = null);
    }
  }

  Future<void> save() async {
    _validatePrincipal();
    _validateRate();
    if (partyError != null || principalError != null || rateError != null) return;

    final p = double.tryParse(principal.text.trim());
    final rPct = double.tryParse(ratePct.text.trim());
    if (partyId == null) { setState(() => error = 'Select party'); return; }
    if (p == null || p <= 0) { setState(() => error = 'Valid principal required'); return; }
    if (rPct == null || rPct < 0) { setState(() => error = 'Valid rate % required'); return; }
    setState(() { busy = true; error = null; });
    try {
      // UI accepts % (18), DB stores decimal (0.18)
      final rateDecimal = rPct / 100;
      final tm = int.tryParse(tenureMonths.text.trim()) ?? 12;
      final data = {
        'party_id': partyId,
        'principal_amount': p,
        'rate': rateDecimal,
        'rate_type': rateType,
        'calculation_method': method,
        'day_base': dayBase,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'direction': direction,
        'loan_type': loanType,
        'tenure_months': tm,
        'remarks': remarks.text.trim().isEmpty ? null : remarks.text.trim(),
      };
      if (widget.loanId != null) {
        await Supabase.instance.client.rpc('update_loan_terms', params: {
          'p_loan_id': widget.loanId,
          'p_party_id': partyId,
          'p_principal_amount': p,
          'p_rate': rateDecimal,
          'p_rate_type': rateType,
          'p_calculation_method': method,
          'p_day_base': dayBase,
          'p_start_date': startDate.toIso8601String().substring(0, 10),
          'p_due_date': dueDate?.toIso8601String().substring(0, 10),
          'p_tenure_days': null,
          'p_tenure_months': int.tryParse(tenureMonths.text.trim()) ?? 12,
          'p_loan_type': loanType,
          'p_direction': direction,
          'p_tds_pct': tdsPct,
          'p_remarks': remarks.text.trim().isEmpty ? null : remarks.text.trim(),
        });
      } else {
        final row = await Supabase.instance.client
            .from('loans')
            .insert(data)
            .select('id')
            .single();
        await AuditLog.write(
            table: 'loans',
            rowId: (row['id'] ?? '').toString(),
            action: 'insert',
            newData: data);
      }
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
    if (loading) {
      return const AlertDialog(
        content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
      );
    }
    final parties = ref.watch(partiesProvider);
    return AlertDialog(
      title: Text(widget.loanId != null ? 'Edit Loan' : 'Add Loan'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              parties.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Parties error: $e'),
                data: (list) => DropdownButtonFormField<String>(
                  initialValue: partyId,
                  hint: const Text('Party *'),
                  items: list.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (v) => setState(() => partyId = v),
                ),
              ),
              if (partyError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(partyError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: principal, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Principal Rs *', errorText: principalError))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: ratePct, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Rate % annual * e.g. 18', errorText: rateError))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(initialValue: direction, items: const [DropdownMenuItem(value: 'receivable', child: Text('Lent out')), DropdownMenuItem(value: 'payable', child: Text('Borrowed'))], onChanged: (v) => setState(() => direction = v!))),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<String>(initialValue: method, items: const [DropdownMenuItem(value: 'daily_accrual', child: Text('Daily accrual')), DropdownMenuItem(value: 'reducing_balance', child: Text('EMI reducing'))], onChanged: (v) => setState(() => method = v!))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: DropdownButtonFormField<int>(initialValue: dayBase, items: const [DropdownMenuItem(value: 360, child: Text('360 banker')), DropdownMenuItem(value: 365, child: Text('365 actual'))], onChanged: (v) => setState(() => dayBase = v!))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: tenureMonths, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tenure (months)'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('Start: ${BsDate.dual(startDate)}')),
                TextButton(onPressed: () async {
                  final d = await BsPicker.pick(context, initialDate: startDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) setState(() => startDate = d);
                }, child: const Text('Pick')),
              ]),
              const SizedBox(height: 12),
              TextField(controller: remarks, decoration: const InputDecoration(labelText: 'Remarks')),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Please wait...' : (widget.loanId != null ? 'Update loan' : 'Save loan'))),
      ],
    );
  }
}
