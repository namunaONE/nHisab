import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/budget/budget_calculator.dart';
import '../../core/calculator/loan_calculator.dart';
import '../accounts/accounts_provider.dart';
import '../budgets/budgets_provider.dart';
import '../loans/loans_provider.dart';
import '../parties/parties_provider.dart';
import '../transactions/transactions_provider.dart';
import 'seed_data.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  bool busy = false;
  String log = '';

  Future<String?> findOrCreateParty(String name) async {
    final client = Supabase.instance.client;
    final existing = await client.from('parties').select('id').eq('name', name).limit(1);
    if ((existing as List).isNotEmpty) return (existing.first as Map)['id'] as String;
    final ins = await client.from('parties').insert({'name': name}).select('id').single();
    return (ins as Map)['id'] as String;
  }

  Future<void> seed21() async {
    setState(() { busy = true; log = 'Checking existing data...'; });
    try {
      final client = Supabase.instance.client;
      final existingLoans = await client.from('loans').select('id').filter('deleted_at', 'is', null).limit(1);
      if ((existingLoans as List).isNotEmpty) {
        setState(() => log = 'Guard: loans table not empty. Aborted to avoid duplicates. Archive or clean DB to reseed.');
        return;
      }
      final existingParties = await client.from('parties').select('id').filter('deleted_at', 'is', null).limit(1);
      if ((existingParties as List).isNotEmpty) {
        setState(() => log = 'Guard: parties table not empty. Aborted to avoid duplicates.');
        return;
      }
      setState(() => log = 'Seeding 21 rows...');
      var n = 0;
      for (final s in seedLoans) {
        final pid = await findOrCreateParty(s.party);
        await client.from('loans').insert({
          'party_id': pid,
          'principal_amount': s.principal,
          'rate': s.rate,
          'rate_type': 'annual',
          'calculation_method': 'daily_accrual',
          'day_base': 360,
          'start_date': s.startDate,
          'direction': s.direction,
          'loan_type': s.loanType,
          'remarks': s.remarks,
        });
        n++;
      }
      ref.invalidate(loansProvider);
      ref.invalidate(partiesProvider);
      setState(() => log = 'Seeded $n loans. Verify totals in Ledger with Today 2026-10-15.');
    } catch (e) {
      setState(() => log = 'Seed error: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickExcel() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    if (res == null || res.files.single.bytes == null) return;
    setState(() { busy = true; log = 'Parsing Excel...'; });
    try {
      final excel = Excel.decodeBytes(res.files.single.bytes!);
      var n = 0;
      for (final table in excel.tables.values) {
        for (var i = 1; i < table.maxRows; i++) {
          final row = table.row(i);
          if (row.length < 5) continue;
          final dateStr = row[1]?.value?.toString() ?? '';
          final party = row[2]?.value?.toString() ?? '';
          final amt = double.tryParse(row[3]?.value?.toString() ?? '');
          final rate = double.tryParse(row[4]?.value?.toString() ?? '');
          if (party.isEmpty || amt == null) continue;
          DateTime start;
          try {
            start = DateTime.parse(dateStr);
          } catch (_) {
            final parts = dateStr.split('/');
            if (parts.length == 3) {
              start = DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
            } else {
              continue;
            }
          }
          final pid = await findOrCreateParty(party);
          await Supabase.instance.client.from('loans').insert({
            'party_id': pid,
            'principal_amount': amt,
            'rate': rate ?? 0,
            'rate_type': 'annual',
            'calculation_method': 'daily_accrual',
            'day_base': 360,
            'start_date': start.toIso8601String().substring(0, 10),
            'direction': 'receivable',
            'loan_type': 'personal',
            'remarks': 'excel-import',
          });
          n++;
        }
      }
      ref.invalidate(loansProvider);
      ref.invalidate(partiesProvider);
      setState(() => log = 'Imported $n rows from Excel.');
    } catch (e) {
      setState(() => log = 'Import error: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exportExcel() async {
    final loans = ref.read(loansProvider).valueOrNull ?? [];
    final today = ref.read(todayProvider);
    final excel = Excel.createExcel();
    final sheet = excel['Ledger'];
    sheet.appendRow([TextCellValue('Sn'), TextCellValue('Date'), TextCellValue('Party Name'), TextCellValue('Amount'), TextCellValue('Rate'), TextCellValue('Today Date'), TextCellValue('Due Days'), TextCellValue('Per Day'), TextCellValue('Interest'), TextCellValue('Amount Paid'), TextCellValue('Dues'), TextCellValue('Total Amount'), TextCellValue('Remarks')]);
    final fmt = NumberFormat('#,##0.00');
    var sn = 0;
    for (final l in loans) {
      sn++;
      final annual = LoanCalculator.annualRate(rate: l.rate, rateType: l.rateType);
      final days = LoanCalculator.dueDays(start: l.startDate, today: today);
      final per = LoanCalculator.perDay(principal: l.principal, annualRateDecimal: annual, dayBase: l.dayBase);
      final interest = LoanCalculator.interest(perDayAmount: per, dueDaysCount: days);
      final dues = (interest - l.paid).clamp(0, double.infinity).toDouble();
      final total = LoanCalculator.total(principal: l.principal, interestAmount: interest, paid: l.paid);
      sheet.appendRow([
        IntCellValue(sn),
        TextCellValue('${l.startDate.year}/${l.startDate.month}/${l.startDate.day}'),
        TextCellValue(l.partyName),
        TextCellValue(fmt.format(l.principal)),
        TextCellValue(l.rate.toString()),
        TextCellValue('${today.year}/${today.month}/${today.day}'),
        IntCellValue(days),
        TextCellValue(fmt.format(per)),
        TextCellValue(fmt.format(interest)),
        TextCellValue(fmt.format(l.paid)),
        TextCellValue(fmt.format(dues)),
        TextCellValue(fmt.format(total)),
        TextCellValue(''),
      ]);
    }
    excel.save(fileName: 'nhisab-ledger.xlsx');
    setState(() => log = 'Exported ${loans.length} rows to nhisab-ledger.xlsx');
  }

  Future<void> exportFullExcel() async {
    final loans = ref.read(loansProvider).valueOrNull ?? [];
    final txns = ref.read(transactionsProvider).valueOrNull ?? [];
    final budgets = ref.read(budgetsProvider).valueOrNull ?? [];
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    final today = ref.read(todayProvider);
    final excel = Excel.createExcel();
    final ledger = excel['Ledger'];
    ledger.appendRow([TextCellValue('Sn'), TextCellValue('Date'), TextCellValue('Party Name'), TextCellValue('Amount'), TextCellValue('Rate'), TextCellValue('Today Date'), TextCellValue('Due Days'), TextCellValue('Per Day'), TextCellValue('Interest'), TextCellValue('Amount Paid'), TextCellValue('Dues'), TextCellValue('Total Amount'), TextCellValue('Remarks')]);
    final fmt = NumberFormat('#,##0.00');
    var sn = 0;
    for (final l in loans) {
      sn++;
      final annual = LoanCalculator.annualRate(rate: l.rate, rateType: l.rateType);
      final days = LoanCalculator.dueDays(start: l.startDate, today: today);
      final per = LoanCalculator.perDay(principal: l.principal, annualRateDecimal: annual, dayBase: l.dayBase);
      final interest = LoanCalculator.interest(perDayAmount: per, dueDaysCount: days);
      final dues = (interest - l.paid).clamp(0, double.infinity).toDouble();
      final total = LoanCalculator.total(principal: l.principal, interestAmount: interest, paid: l.paid);
      ledger.appendRow([
        IntCellValue(sn),
        TextCellValue('${l.startDate.year}/${l.startDate.month}/${l.startDate.day}'),
        TextCellValue(l.partyName),
        TextCellValue(fmt.format(l.principal)),
        TextCellValue(l.rate.toString()),
        TextCellValue('${today.year}/${today.month}/${today.day}'),
        IntCellValue(days),
        TextCellValue(fmt.format(per)),
        TextCellValue(fmt.format(interest)),
        TextCellValue(fmt.format(l.paid)),
        TextCellValue(fmt.format(dues)),
        TextCellValue(fmt.format(total)),
        TextCellValue(''),
      ]);
    }
    final sheetTx = excel['Transactions'];
    sheetTx.appendRow([TextCellValue('Date'), TextCellValue('Wallet'), TextCellValue('Category'), TextCellValue('Kind'), TextCellValue('Amount'), TextCellValue('Loan-linked')]);
    for (final t in txns) {
      sheetTx.appendRow([
        TextCellValue('${t.date.year}/${t.date.month}/${t.date.day}'),
        TextCellValue(t.accountName),
        TextCellValue(t.categoryName ?? ''),
        TextCellValue(t.kind),
        TextCellValue(fmt.format(t.amount)),
        TextCellValue(''),
      ]);
    }
    final sheetBud = excel['Budgets'];
    sheetBud.appendRow([TextCellValue('Category'), TextCellValue('FY'), TextCellValue('Month'), TextCellValue('Limit'), TextCellValue('Spent'), TextCellValue('Left')]);
    for (final b in budgets) {
      sheetBud.appendRow([
        TextCellValue(b.categoryName),
        IntCellValue(b.fyYear),
        IntCellValue(b.fyMonth),
        TextCellValue(fmt.format(b.limit)),
        TextCellValue(fmt.format(b.spent)),
        TextCellValue(fmt.format(BudgetCalculator.budgetRemaining(limit: b.limit, spent: b.spent))),
      ]);
    }
    final sheetAcc = excel['Accounts'];
    sheetAcc.appendRow([TextCellValue('Wallet'), TextCellValue('Type'), TextCellValue('Opening'), TextCellValue('Balance')]);
    for (final a in accounts) {
      sheetAcc.appendRow([
        TextCellValue(a.name),
        TextCellValue(a.type),
        TextCellValue(fmt.format(a.openingBalance)),
        TextCellValue(fmt.format(a.computedBalance)),
      ]);
    }
    excel.delete('Sheet1');
    excel.save(fileName: 'nhisab-full.xlsx');
    setState(() => log = 'Exported ${loans.length} loans + ${txns.length} txns + ${budgets.length} budgets.');
  }

  Future<void> exportPdfSummary() async {
    final loans = ref.read(loansProvider).valueOrNull ?? [];
    final txns = ref.read(transactionsProvider).valueOrNull ?? [];
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    final today = ref.read(todayProvider);
    final fmt = NumberFormat('#,##0.00');
    var loanPrincipal = 0.0;
    for (final l in loans) {
      loanPrincipal += l.principal;
    }
    var cashIn = 0.0;
    var cashOut = 0.0;
    for (final t in txns) {
      if (t.kind == 'income') {
        cashIn += t.amount;
      } else if (t.kind == 'expense') {
        cashOut += t.amount;
      }
    }
    var wallets = 0.0;
    for (final a in accounts) {
      wallets += a.computedBalance;
    }
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('nHisab Summary',
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
              'As of ${today.year}/${today.month}/${today.day} • ${BudgetCalculator.fyLabel(today)}'),
          pw.SizedBox(height: 12),
          pw.Text('Wallets total: Rs ${fmt.format(wallets)}'),
          pw.Text('Active loans (filter): ${loans.length} • principal Rs ${fmt.format(loanPrincipal)}'),
          pw.Text('Cash in: Rs ${fmt.format(cashIn)} • out: Rs ${fmt.format(cashOut)}'),
          pw.SizedBox(height: 12),
          pw.Text('Generated on-device. NUMERIC(15,2) source of truth in Supabase.'),
        ],
      ),
    ));
    await Printing.sharePdf(
        bytes: await doc.save(), filename: 'nhisab-summary.pdf');
    setState(() => log = 'Shared nhisab-summary.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import / Export')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('21 rows transcribed from sheet. Group A 57L, Group B 85713900 (Row4 fixed missing zero), Group C 42.6L.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: busy ? null : seed21, child: Text(busy ? 'Working...' : 'Seed 21 rows to Supabase')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : pickExcel, child: const Text('Import Excel .xlsx (Date, Party, Amount, Rate)')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : exportExcel, child: const Text('Export current ledger to Excel')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : exportFullExcel, child: const Text('Export full workbook (Ledger + Txns + Budgets + Wallets)')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : exportPdfSummary, child: const Text('Share PDF summary')),
            const SizedBox(height: 12),
            Text(log),
          ],
        ),
      ),
    );
  }
}
