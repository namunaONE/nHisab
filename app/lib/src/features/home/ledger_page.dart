import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import '../../core/calculator/loan_calculator.dart';
import '../../core/dates/bs_date.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton.dart';
import '../home/home_shell.dart';
import '../loans/emi_schedule_page.dart';
import '../loans/loan_form.dart';
import '../loans/loan_model.dart';
import '../loans/loans_provider.dart';

class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key});

  /// Extract per-loan row data once, reused by both desktop table and mobile cards.
  static List<_LoanRowData> _rows(List<LoanRow> loans, DateTime today,
      NumberFormat fmt, ColorScheme scheme, WidgetRef ref) {
    final out = <_LoanRowData>[];
    var sn = 0;
    for (final l in loans) {
      sn++;
      final annual = LoanCalculator.annualRate(rate: l.rate, rateType: l.rateType);
      final days = LoanCalculator.dueDays(start: l.startDate, today: today);
      final per = LoanCalculator.perDay(principal: l.principal, annualRateDecimal: annual, dayBase: l.dayBase);
      final interest = LoanCalculator.interest(perDayAmount: per, dueDaysCount: days);
      final dues = (interest - l.paid).clamp(0, double.infinity).toDouble();
      final total = LoanCalculator.total(principal: l.principal, interestAmount: interest, paid: l.paid);
      out.add(_LoanRowData(
        sn: sn,
        loan: l,
        days: days,
        per: per,
        interest: interest,
        dues: dues,
        total: total,
      ));
    }
    return out;
  }

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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;
                return loansAsync.when(
                  loading: () => const SkeletonList(itemCount: 4),
                  error: (e, _) => ErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(loansProvider),
                  ),
                  data: (loans) {
                    final rows = _rows(loans, today, fmt, scheme, ref);
                    if (loans.isEmpty) {
                      return EmptyState(
                        icon: Icons.table_chart,
                        title: 'No loans yet',
                        subtitle:
                            'Add a party and loan to start tracking interest and dues.',
                        ctaLabel: 'Add loan',
                        onCta: () => showDialog(
                            context: context,
                            builder: (_) => const LoanFormDialog()),
                      );
                    }
                    if (isMobile) {
                      return _mobileBody(context, rows, fmt, scheme, ref);
                    }
                    return _desktopBody(context, loans, rows, today, fmt, scheme, ref);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Desktop - 13-column DataTable (minWidth 1400 + horizontal scroll)
  // =========================================================================
  Widget _desktopBody(BuildContext context, List<LoanRow> loans, List<_LoanRowData> rows, DateTime today,
      NumberFormat fmt, ColorScheme scheme, WidgetRef ref) {
    double tP = 0, tPer = 0, tI = 0, tPaid = 0, tDues = 0, tT = 0;
    for (final l in loans) {
      tP += l.principal;
      tPer += rows.firstWhere((r) => r.loan.id == l.id).per;
      tI += rows.firstWhere((r) => r.loan.id == l.id).interest;
      tPaid += l.paid;
      tDues += rows.firstWhere((r) => r.loan.id == l.id).dues;
      tT += rows.firstWhere((r) => r.loan.id == l.id).total;
    }

    final dataRows = <DataRow>[];
    for (final r in rows) {
      dataRows.add(DataRow(cells: [
        DataCell(Text('${r.sn}')),
        DataCell(Text('${r.loan.startDate.year}/${r.loan.startDate.month}/${r.loan.startDate.day}')),
        DataCell(Text(r.loan.partyName)),
        DataCell(Text(fmt.format(r.loan.principal))),
        DataCell(Text(r.loan.rate.toStringAsFixed(4))),
        DataCell(Text('${today.year}/${today.month}/${today.day}')),
        DataCell(Text('${r.days}')),
        DataCell(Text(fmt.format(r.per))),
        DataCell(Text(fmt.format(r.interest))),
        DataCell(Text(fmt.format(r.loan.paid))),
        DataCell(Text(fmt.format(r.dues), style: TextStyle(color: scheme.error))),
        DataCell(Text(fmt.format(r.total), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold))),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.calendar_today, size: 18),
              tooltip: 'View EMI schedule',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EmiSchedulePage(loanId: r.loan.id)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.archive_outlined, size: 18),
              tooltip: 'Archive loan',
              onPressed: () async {
                await Supabase.instance.client
                    .from('loans')
                    .update({'deleted_at': DateTime.now().toIso8601String()})
                    .eq('id', r.loan.id);
                await AuditLog.write(
                    table: 'loans', rowId: r.loan.id, action: 'archive');
                ref.invalidate(loansProvider);
              },
            ),
          ],
        )),
      ]));
    }

    return DataTable2(
      columnSpacing: 12,
      minWidth: 1400,
      columns: const [
        DataColumn(label: Text('Sn')),
        DataColumn(label: Text('Date')),
        DataColumn(label: Text('Party Name')),
        DataColumn(label: Text('Amount')),
        DataColumn(label: Text('Rate')),
        DataColumn(label: Text('Today Date')),
        DataColumn(label: Text('Due Days')),
        DataColumn(label: Text('Per Day')),
        DataColumn(label: Text('Interest')),
        DataColumn(label: Text('Amount Paid')),
        DataColumn(label: Text('Dues')),
        DataColumn(label: Text('Total Amount')),
        DataColumn(label: Text('Remarks')),
      ],
      rows: [
        ...dataRows,
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
  }

  // =========================================================================
  // Mobile - card list under 600px
  // =========================================================================
  Widget _mobileBody(BuildContext context, List<_LoanRowData> rows, NumberFormat fmt,
      ColorScheme scheme, WidgetRef ref) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No loans yet. Tap + to add one.', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        final l = r.loan;
        return Card.outlined(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(r.sn.toString(), style: Theme.of(context).textTheme.labelSmall),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.calendar_today, size: 18),
                      tooltip: 'View EMI schedule',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => EmiSchedulePage(loanId: l.id)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      tooltip: 'Archive loan',
                      onPressed: () async {
                        await Supabase.instance.client
                            .from('loans')
                            .update({'deleted_at': DateTime.now().toIso8601String()})
                            .eq('id', l.id);
                        await AuditLog.write(
                            table: 'loans', rowId: l.id, action: 'archive');
                        ref.invalidate(loansProvider);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.partyName,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text('${l.startDate.year}/${l.startDate.month}/${l.startDate.day}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        fmt.format(r.total),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _pill(scheme, 'Amount', fmt.format(l.principal)),
                    _pill(scheme, 'Rate', l.rate.toStringAsFixed(2)),
                    _pill(scheme, 'Due Days', '${r.days}'),
                    _pill(scheme, 'Per Day', fmt.format(r.per)),
                    _pill(scheme, 'Interest', fmt.format(r.interest)),
                    _pill(scheme, 'Paid', fmt.format(l.paid)),
                    _pill(scheme, 'Dues', fmt.format(r.dues),
                        valueColor: scheme.error),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill(ColorScheme scheme, String label, String value,
      {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
        Text(value,
            style: TextStyle(fontSize: 14, color: valueColor ?? scheme.onSurface)),
      ],
    );
  }
}

/// Carries calculated row data shared by desktop table and mobile cards.
class _LoanRowData {
  final int sn;
  final LoanRow loan;
  final int days;
  final double per;
  final double interest;
  final double dues;
  final double total;

  _LoanRowData({
    required this.sn,
    required this.loan,
    required this.days,
    required this.per,
    required this.interest,
    required this.dues,
    required this.total,
  });
}
