import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../parties/parties_provider.dart';
import 'loans_provider.dart';

class LoanFormDialog extends ConsumerStatefulWidget {
  const LoanFormDialog({super.key});
  @override
  ConsumerState<LoanFormDialog> createState() => _LoanFormDialogState();
}

class _LoanFormDialogState extends ConsumerState<LoanFormDialog> {
  String? partyId;
  final principal = TextEditingController();
  final ratePct = TextEditingController(text: '18');
  String rateType = 'annual';
  String method = 'daily_accrual';
  int dayBase = 360;
  String direction = 'receivable';
  String loanType = 'personal';
  DateTime startDate = DateTime.now();
  final remarks = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> save() async {
    final p = double.tryParse(principal.text.trim());
    final rPct = double.tryParse(ratePct.text.trim());
    if (partyId == null) { setState(() => error = 'Select party'); return; }
    if (p == null || p <= 0) { setState(() => error = 'Valid principal required'); return; }
    if (rPct == null || rPct < 0) { setState(() => error = 'Valid rate % required'); return; }
    setState(() { busy = true; error = null; });
    try {
      // UI accepts % (18), DB stores decimal (0.18)
      final rateDecimal = rPct / 100;
      await Supabase.instance.client.from('loans').insert({
        'party_id': partyId,
        'principal_amount': p,
        'rate': rateDecimal,
        'rate_type': rateType,
        'calculation_method': method,
        'day_base': dayBase,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'direction': direction,
        'loan_type': loanType,
        'remarks': remarks.text.trim().isEmpty ? null : remarks.text.trim(),
      });
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
    final parties = ref.watch(partiesProvider);
    return AlertDialog(
      title: const Text('Add Loan'),
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
                  value: partyId,
                  hint: const Text('Party *'),
                  items: list.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (v) => setState(() => partyId = v),
                ),
              ),
              Row(children: [
                Expanded(child: TextField(controller: principal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Principal Rs *'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: ratePct, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rate % annual * e.g. 18'))),
              ]),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(value: direction, items: const [DropdownMenuItem(value: 'receivable', child: Text('Lent out')), DropdownMenuItem(value: 'payable', child: Text('Borrowed'))], onChanged: (v) => setState(() => direction = v!))),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<String>(value: method, items: const [DropdownMenuItem(value: 'daily_accrual', child: Text('Daily accrual')), DropdownMenuItem(value: 'reducing_balance', child: Text('EMI reducing'))], onChanged: (v) => setState(() => method = v!))),
              ]),
              Row(children: [
                Expanded(child: DropdownButtonFormField<int>(value: dayBase, items: const [DropdownMenuItem(value: 360, child: Text('360 banker')), DropdownMenuItem(value: 365, child: Text('365 actual'))], onChanged: (v) => setState(() => dayBase = v!))),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<String>(value: loanType, items: const [DropdownMenuItem(value: 'personal', child: Text('Personal')), DropdownMenuItem(value: 'business', child: Text('Business')), DropdownMenuItem(value: 'home', child: Text('Home')), DropdownMenuItem(value: 'vehicle', child: Text('Vehicle')), DropdownMenuItem(value: 'cash_credit', child: Text('Cash Credit')), DropdownMenuItem(value: 'demand', child: Text('Demand'))], onChanged: (v) => setState(() => loanType = v!))),
              ]),
              Row(children: [
                Text('Start: ${startDate.year}/${startDate.month}/${startDate.day}'),
                TextButton(onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: startDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) setState(() => startDate = d);
                }, child: const Text('Pick')),
              ]),
              TextField(controller: remarks, decoration: const InputDecoration(labelText: 'Remarks')),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Saving...' : 'Save loan')),
      ],
    );
  }
}
