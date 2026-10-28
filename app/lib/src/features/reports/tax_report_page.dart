import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TaxReportPage extends ConsumerStatefulWidget {
  const TaxReportPage({super.key});
  @override
  ConsumerState<TaxReportPage> createState() => _TaxReportPageState();
}

class _TaxReportPageState extends ConsumerState<TaxReportPage> {
  double vatOutput = 0, vatInput = 0, tdsTotal = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final vat = await client.from('vat_ledger').select('entry_type, vat_amount') as List;
      for (final r in vat) {
        final amt = (r['vat_amount'] as num?)?.toDouble() ?? 0;
        if (r['entry_type'] == 'output') {
          vatOutput += amt;
        } else {
          vatInput += amt;
        }
      }
      final tds = await client.from('tds_ledger').select('tds_amount') as List;
      for (final r in tds) {
        tdsTotal += (r['tds_amount'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tax / Compliance Report (Tier C)')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('VAT (13%)', style: TextStyle(fontWeight: FontWeight.bold)),
                ListTile(title: const Text('Output VAT'), trailing: Text(vatOutput.toStringAsFixed(2))),
                ListTile(title: const Text('Input VAT'), trailing: Text(vatInput.toStringAsFixed(2))),
                ListTile(title: const Text('Net VAT payable'), trailing: Text((vatOutput - vatInput).toStringAsFixed(2))),
                const Divider(),
                const Text('TDS', style: TextStyle(fontWeight: FontWeight.bold)),
                ListTile(title: const Text('Total TDS'), trailing: Text(tdsTotal.toStringAsFixed(2))),
                const SizedBox(height: 16),
                const Text(
                  'Note: This is a report-only view. VAT/TDS filing, CBMS e-billing, '
                  'KYC/AML verification, goAML export and Nepal data residency are '
                  'Tier C items requiring legal/compliance review before production use.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
    );
  }
}