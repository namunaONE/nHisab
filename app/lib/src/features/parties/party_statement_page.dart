import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'party_statement_model.dart';
import 'party_statement_provider.dart';

class PartyStatementPage extends ConsumerWidget {
  final String partyId;
  const PartyStatementPage({super.key, required this.partyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stmtAsync = ref.watch(partyStatementProvider(partyId));
    final stmt = stmtAsync.valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Party Statement'),
        actions: [
          if (stmt != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Export PDF Statement',
              onPressed: () async {
                await _exportPdf(context, stmt);
              },
            ),
        ],
      ),
      body: stmtAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stmt) => _buildBody(context, stmt, fmt, scheme, ref),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PartyStatement stmt, NumberFormat fmt,
      ColorScheme scheme, WidgetRef ref) {
    final isRec = stmt.isReceivable;
    return Column(
      children: [
        // Party info card
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
                        stmt.partyName,
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
                        color: isRec
                            ? scheme.secondary.withValues(alpha: 0.2)
                            : scheme.error.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        stmt.directionLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isRec ? scheme.secondary : scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                if (stmt.phone != null || stmt.address != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      if (stmt.phone != null)
                        Text(stmt.phone!,
                            style: Theme.of(context).textTheme.bodySmall),
                      if (stmt.address != null) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.home, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(stmt.address!,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Summary row
                Row(
                  children: [
                    _summaryChip('Total Lent', fmt.format(stmt.totalPrincipal),
                        scheme.primary),
                    const SizedBox(width: 8),
                    _summaryChip('Total Repaid',
                        fmt.format(stmt.totalPrincipalPaid + stmt.totalInterestPaid),
                        scheme.secondary),
                    const SizedBox(width: 8),
                    _summaryChip('Interest Due',
                        fmt.format(stmt.totalInterestAccrued - stmt.totalInterestPaid),
                        stmt.outstanding >= 0 ? scheme.error : scheme.secondary),
                    const SizedBox(width: 8),
                    _summaryChip('Outstanding', fmt.format(stmt.outstanding),
                        stmt.outstanding >= 0 ? scheme.error : scheme.secondary,
                        isBold: true),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Statement table
        Expanded(
          child: stmt.rows.isEmpty
              ? const Center(
                  child: Text('No transactions for this party.'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Description')),
                      DataColumn(label: Text('Debit')),
                      DataColumn(label: Text('Credit')),
                      DataColumn(label: Text('Balance')),
                    ],
                    rows: [
                      ...stmt.rows.map((r) => DataRow(cells: [
                        DataCell(Text('${r.date.year}/${r.date.month}/${r.date.day}')),
                        DataCell(Text(_typeLabel(r.type))),
                        DataCell(Text(r.description)),
                        DataCell(Text(
                          r.debit > 0 ? fmt.format(r.debit) : '',
                          style: TextStyle(
                              color: scheme.error, fontWeight: FontWeight.bold),
                        )),
                        DataCell(Text(
                          r.credit > 0 ? fmt.format(r.credit) : '',
                          style: TextStyle(
                              color: scheme.secondary, fontWeight: FontWeight.bold),
                        )),
                        DataCell(Text(
                          fmt.format(r.balance),
                          style: TextStyle(
                              color: scheme.primary, fontWeight: FontWeight.bold),
                        )),
                      ])),
                      DataRow(color: WidgetStatePropertyAll(scheme.surfaceContainerHigh), cells: [
                        const DataCell(Text('')),
                        const DataCell(Text('')),
                        const DataCell(Text('TOTAL',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(
                            fmt.format(stmt.rows
                                    .fold(0.0, (s, r) => s + r.debit))
                                .toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(
                            fmt.format(stmt.rows
                                    .fold(0.0, (s, r) => s + r.credit))
                                .toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(
                            fmt.format(stmt.outstanding),
                            style: const TextStyle(fontWeight: FontWeight.bold))),
                      ]),
                    ],
                  ),
                ),
        ),
      ],
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

  String _typeLabel(String type) {
    switch (type) {
      case 'loan_disbursal':
        return 'Loan Disbursal';
      case 'payment':
        return 'Payment';
      case 'interest_accrual':
        return 'Interest Accrued';
      case 'write_off':
        return 'Write-off';
      default:
        return type;
    }
  }

  Future<void> _exportPdf(BuildContext context, PartyStatement stmt) async {
    final fmt = NumberFormat('#,##0.00');
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('nHisab - Party Statement',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Party: ${stmt.partyName}'),
          if (stmt.phone != null) pw.Text('Phone: ${stmt.phone}'),
          if (stmt.address != null) pw.Text('Address: ${stmt.address}'),
          pw.Text('Type: ${stmt.directionLabel}'),
          pw.Text('As of: ${stmt.asOfDate.year}/${stmt.asOfDate.month}/${stmt.asOfDate.day}'),
          pw.SizedBox(height: 12),
          pw.Text('Summary',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(
              'Total Principal: ${fmt.format(stmt.totalPrincipal)}'),
          pw.Text('Total Repaid: ${fmt.format(stmt.totalPrincipalPaid + stmt.totalInterestPaid)}'),
          pw.Text(
              'Interest Due: ${fmt.format(stmt.totalInterestAccrued - stmt.totalInterestPaid)}'),
          if (stmt.totalWrittenOff > 0)
            pw.Text('Written off: ${fmt.format(stmt.totalWrittenOff)}'),
          pw.Text('Outstanding: ${fmt.format(stmt.outstanding)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('Statement',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: pw.FixedColumnWidth(70),
              1: pw.FixedColumnWidth(100),
              2: pw.FixedColumnWidth(150),
              3: pw.FixedColumnWidth(70),
              4: pw.FixedColumnWidth(70),
              5: pw.FixedColumnWidth(80),
            },
            children: [
              pw.TableRow(
                children: ['Date', 'Type', 'Description', 'Debit', 'Credit', 'Balance']
                    .map((h) => pw.Container(
                  padding: pw.EdgeInsets.all(4),
                  child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                )).toList(),
              ),
              ...stmt.rows.map((r) => pw.TableRow(
                children: [
                  '${r.date.year}/${r.date.month}/${r.date.day}',
                  _typeLabel(r.type),
                  r.description,
                  r.debit > 0 ? fmt.format(r.debit) : '',
                  r.credit > 0 ? fmt.format(r.credit) : '',
                  fmt.format(r.balance),
                ].map((cell) => pw.Container(
                  padding: pw.EdgeInsets.all(4),
                  child: pw.Text(cell),
                )).toList(),
              )),
            ],
          ),
        ],
      ),
    ));
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'party_statement_${stmt.partyName}.pdf');
  }
}
