import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'emi_schedule_model.dart';
import 'emi_schedule_provider.dart';

class EmiSchedulePage extends ConsumerWidget {
  final String loanId;
  const EmiSchedulePage({super.key, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedAsync = ref.watch(emiScheduleProvider(loanId));
    final stmt = schedAsync.valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('EMI Schedule'),
        actions: [
          if (stmt != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Export PDF Schedule',
              onPressed: () => _exportPdf(context, stmt),
            ),
        ],
      ),
      body: schedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sched) => _buildBody(context, sched, fmt, scheme),
      ),
    );
  }

  Widget _buildBody(BuildContext context, EmiSchedule sched, NumberFormat fmt,
      ColorScheme scheme) {
    if (!sched.hasSchedule) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No EMI schedule for this loan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${sched.calculationMethod} loans use daily accrual, not EMI amortization.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final dataRows = <DataRow>[
      for (final inst in sched.installments)
        DataRow(
          color: WidgetStatePropertyAll(
            inst.isOverdue ? scheme.error.withValues(alpha: 0.1) : null,
          ),
          cells: [
            DataCell(Text('${inst.installmentNo}',
                style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(
                '${inst.dueDate.year}/${inst.dueDate.month}/${inst.dueDate.day}')),
            DataCell(Text(fmt.format(inst.principalDue))),
            DataCell(Text(fmt.format(inst.interestDue))),
            DataCell(Text(fmt.format(inst.totalDue),
                style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(_statusBadge(inst.status, scheme)),
            DataCell(Text(inst.paidDate != null
                ? '${inst.paidDate!.year}/${inst.paidDate!.month}/${inst.paidDate!.day}'
                : '-')),
            DataCell(Text(inst.paidAmount != null
                ? fmt.format(inst.paidAmount!)
                : '-')),
          ],
        ),
    ];

    return Column(
      children: [
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sched.partyName,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Reducing Balance',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _summaryChip('Principal', fmt.format(sched.principal),
                        scheme.primary),
                    const SizedBox(width: 8),
                    _summaryChip('Monthly EMI', fmt.format(sched.emiAmount),
                        scheme.secondary),
                    const SizedBox(width: 8),
                    _summaryChip('Total Interest',
                        fmt.format(sched.totalInterest), scheme.error),
                    const SizedBox(width: 8),
                    _summaryChip('Total Payable',
                        fmt.format(sched.totalPayable), scheme.primary,
                        isBold: true),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statusChip('Pending', sched.pendingCount, Colors.blue),
                    const SizedBox(width: 8),
                    _statusChip(
                        'Paid', sched.paidCount, Colors.green),
                    const SizedBox(width: 8),
                    _statusChip('Overdue', sched.overdueCount, scheme.error),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: sched.installments.isEmpty
              ? const Center(child: Text('No installments.'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Due Date')),
                      DataColumn(label: Text('Principal')),
                      DataColumn(label: Text('Interest')),
                      DataColumn(label: Text('Total Due')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Paid Date')),
                      DataColumn(label: Text('Paid Amount')),
                    ],
                    rows: dataRows,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _statusColor(status, scheme),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color,
      {bool isBold = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: color,
                )),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 4),
            Text('$count',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                )),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'paid':
        return scheme.secondary;
      case 'overdue':
        return scheme.error;
      case 'pending':
      default:
        return scheme.primary;
    }
  }

  Future<void> _exportPdf(BuildContext context, EmiSchedule sched) async {
    final fmt = NumberFormat('#,##0.00');
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('nHisab - EMI Schedule',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Party: ${sched.partyName}'),
          pw.Text('Loan ID: ${sched.loanId}'),
          pw.Text('Principal: ${fmt.format(sched.principal)}'),
          pw.Text('Annual Rate: ${sched.annualRatePct}%'),
          pw.Text('Monthly EMI: ${fmt.format(sched.emiAmount)}'),
          pw.Text('Tenure: ${sched.months} months'),
          pw.Text('Total Payable: ${fmt.format(sched.totalPayable)}'),
          pw.Text('Total Interest: ${fmt.format(sched.totalInterest)}'),
          pw.SizedBox(height: 12),
          pw.Text('Installments',
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: pw.FixedColumnWidth(40),
              1: pw.FixedColumnWidth(80),
              2: pw.FixedColumnWidth(80),
              3: pw.FixedColumnWidth(80),
              4: pw.FixedColumnWidth(80),
              5: pw.FixedColumnWidth(70),
            },
            children: [
              pw.TableRow(
                children: [
                  '#',
                  'Due Date',
                  'Principal',
                  'Interest',
                  'Total',
                  'Status'
                ]
                    .map((h) => pw.Container(
                          padding: pw.EdgeInsets.all(4),
                          child: pw.Text(h,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold)),
                        ))
                    .toList(),
              ),
              ...sched.installments.map((inst) => pw.TableRow(
                    children: [
                      '${inst.installmentNo}',
                      '${inst.dueDate.year}/${inst.dueDate.month}/${inst.dueDate.day}',
                      fmt.format(inst.principalDue),
                      fmt.format(inst.interestDue),
                      fmt.format(inst.totalDue),
                      inst.status.toUpperCase(),
                    ]
                        .map((cell) => pw.Container(
                              padding: pw.EdgeInsets.all(4),
                              child: pw.Text(cell),
                            ))
                        .toList(),
                  )),
            ],
          ),
        ],
      ),
    ));
    await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'emi_schedule_${sched.loanId}.pdf');
  }
}
