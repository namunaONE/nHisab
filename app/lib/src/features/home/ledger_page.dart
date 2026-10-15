import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/calculator/loan_calculator.dart';
import '../../core/dates/bs_date.dart';
import '../home/home_shell.dart';
import '../loans/loans_provider.dart';

class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansProvider);
    final today = ref.watch(todayProvider);
    final direction = ref.watch(directionFilterProvider);
    final fmt = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('nHisab Ledger'),
        actions: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'receivable', label: Text('Lent')),
              ButtonSegment(value: 'payable', label: Text('Borrowed')),
            ],
            selected: {direction},
            onSelectionChanged: (s) => ref.read(directionFilterProvider.notifier).state = s.first,
          ),
          const SizedBox(width: 8),
          const UserMenu(),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Today: ${BsDate.dual(DateTime(today.year, today.month, today.day))}'),
                ElevatedButton(
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: today, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) ref.read(todayProvider.notifier).state = d;
                  },
                  child: const Text('Change Today'),
                ),
                OutlinedButton(
                  onPressed: () => ref.read(todayProvider.notifier).state = DateTime(2026, 10, 15),
                  child: const Text('Set 2026-10-15 to match sheet'),
                ),
              ],
            ),
          ),
          Expanded(
            child: loansAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Supabase error: $e')),
              data: (loans) {
                double tP = 0, tPer = 0, tI = 0, tPaid = 0, tDues = 0, tT = 0;
                final rows = <DataRow>[];
                var sn = 0;
                for (final l in loans) {
                  sn++;
                  final annual = LoanCalculator.annualRate(rate: l.rate, rateType: l.rateType);
                  final days = LoanCalculator.dueDays(start: l.startDate, today: today);
                  final per = LoanCalculator.perDay(principal: l.principal, annualRateDecimal: annual, dayBase: l.dayBase);
                  final interest = LoanCalculator.interest(perDayAmount: per, dueDaysCount: days);
                  final dues = (interest - l.paid).clamp(0, double.infinity).toDouble();
                  final total = LoanCalculator.total(principal: l.principal, interestAmount: interest, paid: l.paid);
                  tP += l.principal; tPer += per; tI += interest; tPaid += l.paid; tDues += dues; tT += total;
                  rows.add(DataRow(cells: [
                    DataCell(Text('$sn')),
                    DataCell(Text('${l.startDate.year}/${l.startDate.month}/${l.startDate.day}')),
                    DataCell(Text(l.partyName)),
                    DataCell(Text(fmt.format(l.principal))),
                    DataCell(Text(l.rate.toStringAsFixed(4))),
                    DataCell(Text('${today.year}/${today.month}/${today.day}')),
                    DataCell(Text('$days')),
                    DataCell(Text(fmt.format(per))),
                    DataCell(Text(fmt.format(interest))),
                    DataCell(Text(fmt.format(l.paid))),
                    DataCell(Text(fmt.format(dues), style: TextStyle(color: scheme.error))),
                    DataCell(Text(fmt.format(total), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold))),
                    DataCell(IconButton(
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      tooltip: 'Archive loan',
                      onPressed: () async {
                        await Supabase.instance.client.from('loans').update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', l.id);
                        ref.invalidate(loansProvider);
                      },
                    )),
                  ]));
                }
                return DataTable2(
                  columnSpacing: 12,
                  minWidth: 1400,
                  columns: const [
                    DataColumn(label: Text('Sn', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Date', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Party Name', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Amount', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Rate', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Today Date', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Due Days', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Per Day', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Interest', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Amount Paid', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Dues', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Total Amount', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('Remarks', style: TextStyle(color: Colors.white))),
                  ],
                  rows: [
                    ...rows,
                    DataRow(color: WidgetStatePropertyAll(scheme.surfaceContainerHigh), cells: [
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(fmt.format(tP), style: const TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      DataCell(Text(fmt.format(tPer), style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(fmt.format(tI), style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(fmt.format(tPaid), style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(fmt.format(tDues), style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(fmt.format(tT), style: const TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                    ]),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
