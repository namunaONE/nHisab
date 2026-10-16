import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../loans/loans_provider.dart';
import '../../core/calculator/loan_calculator.dart';
import 'party_statement_model.dart';

/// Fetches the complete statement for a party: all loans, all payments,
/// interest accrued up to Today, and running balance.
///
/// Returns []-safe stub if tables are not yet migrated.
final partyStatementProvider = FutureProvider.family<PartyStatement, String>(
  (ref, partyId) async {
    final client = Supabase.instance.client;
    final today = ref.watch(todayProvider);

    // Fetch party info
    final partyRes = await client
        .from('parties')
        .select('id, name, phone, address')
        .eq('id', partyId)
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (partyRes == null) {
      throw Exception('Party not found: $partyId');
    }
    final partyName = (partyRes['name'] ?? '') as String;
    final phone = partyRes['phone'] as String?;
    final address = partyRes['address'] as String?;

    // Fetch all loans for this party
    final loansRes = await client
        .from('loans')
        .select(
            'id, principal_amount, rate, rate_type, day_base, start_date, direction, status')
        .eq('party_id', partyId)
        .filter('deleted_at', 'is', null)
        .order('start_date');
    final loans = (loansRes as List);

    // Fetch all payments for these loans
    final loanIds = loans.map((r) => r['id'] as String).toList();
    List payments = [];
    if (loanIds.isNotEmpty) {
      final paysRes = await client
          .from('payments')
          .select(
              'id, loan_id, payment_date, total_amount, interest_amount, principal_amount')
          .filter('deleted_at', 'is', null);
      payments = (paysRes as List);
    }
    final paymentsByLoan = <String, List<Map>>{};
    for (final p in payments) {
      final lid = p['loan_id'] as String;
      paymentsByLoan.putIfAbsent(lid, () => []).add(p);
    }
    paymentsByLoan.forEach((_, list) {
      list.sort((a, b) {
        final da = DateTime.parse(a['payment_date'] as String);
        final db = DateTime.parse(b['payment_date'] as String);
        return da.compareTo(db);
      });
    });

    // Determine dominant direction first
    int receivableCount = 0;
    int payableCount = 0;
    for (final l in loans) {
      final d = l['direction'] as String;
      if (d == 'receivable') receivableCount++;
      if (d == 'payable') payableCount++;
    }
    final dominantDirection =
        receivableCount >= payableCount ? 'receivable' : 'payable';

    // Build statement rows
    final rows = <StatementRow>[];
    double totalPrincipal = 0;
    double totalPrincipalPaid = 0;
    double totalInterestAccrued = 0;
    double totalInterestPaid = 0;

    for (final l in loans) {
      final loanId = l['id'] as String;
      final principal = (l['principal_amount'] as num).toDouble();
      final rate = (l['rate'] as num).toDouble();
      final rateType = l['rate_type'] as String;
      final dayBase = (l['day_base'] as num?)?.toInt() ?? 360;
      final startDate = DateTime.parse(l['start_date'] as String);
      final direction = l['direction'] as String;

      totalPrincipal += principal;

      // Interest accrued up to Today
      final annual = LoanCalculator.annualRate(rate: rate, rateType: rateType);
      final perDay = LoanCalculator.perDay(
          principal: principal, annualRateDecimal: annual, dayBase: dayBase);
      final dueDays = LoanCalculator.dueDays(start: startDate, today: today);
      final interestAccrued =
          LoanCalculator.interest(perDayAmount: perDay, dueDaysCount: dueDays);
      totalInterestAccrued += interestAccrued;

      // Loan disbursal row
      rows.add(StatementRow(
        id: 'loan-$loanId',
        date: startDate,
        type: 'loan_disbursal',
        description: 'Loan Disbursal',
        debit: direction == 'receivable' ? principal : 0,
        credit: direction == 'payable' ? principal : 0,
        balance: 0,
      ));

      // Payment rows for this loan
      final loanPayments = paymentsByLoan[loanId] ?? [];
      double loanInterestPaid = 0;
      for (final p in loanPayments) {
        final totalAmt = (p['total_amount'] as num).toDouble();
        final intAmt = (p['interest_amount'] as num?)?.toDouble() ?? 0;
        final prinAmt = (p['principal_amount'] as num?)?.toDouble() ?? 0;
        final payDate = DateTime.parse(p['payment_date'] as String);

        totalPrincipalPaid += prinAmt;
        totalInterestPaid += intAmt;
        loanInterestPaid += intAmt;

        rows.add(StatementRow(
          id: p['id'] as String,
          date: payDate,
          type: 'payment',
          description: 'Payment',
          debit: direction == 'payable' ? totalAmt : 0,
          credit: direction == 'receivable' ? totalAmt : 0,
          balance: 0,
        ));
      }

      // Interest accrual row (net interest not yet paid)
      final interestDue = interestAccrued - loanInterestPaid;
      if (interestDue > 0.01) {
        rows.add(StatementRow(
          id: 'interest-$loanId',
          date: today,
          type: 'interest_accrual',
          description: 'Interest Accrued to Date',
          debit: direction == 'receivable' ? interestDue : 0,
          credit: direction == 'payable' ? interestDue : 0,
          balance: 0,
        ));
      }
    }

    // Sort all rows by date, then by type (loan_disbursal before payment on same date)
    rows.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      return a.type.compareTo(b.type);
    });

    // Compute running balance
    double balance = 0;
    final balancedRows = <StatementRow>[];
    for (final r in rows) {
      if (dominantDirection == 'receivable') {
        // Receivable: positive balance = party owes us
        // Debit increases what party owes, credit decreases
        balance += r.debit - r.credit;
      } else {
        // Payable: positive balance = we owe party
        // Credit increases what we owe, debit decreases
        balance += r.credit - r.debit;
      }
      balancedRows.add(StatementRow(
        id: r.id,
        date: r.date,
        type: r.type,
        description: r.description,
        debit: r.debit,
        credit: r.credit,
        balance: balance,
      ));
    }

    final outstanding =
        totalPrincipal - totalPrincipalPaid + totalInterestAccrued - totalInterestPaid;

    return PartyStatement(
      partyId: partyId,
      partyName: partyName,
      phone: phone,
      address: address,
      direction: dominantDirection,
      totalPrincipal: totalPrincipal,
      totalPrincipalPaid: totalPrincipalPaid,
      totalInterestAccrued: totalInterestAccrued,
      totalInterestPaid: totalInterestPaid,
      outstanding: outstanding,
      rows: balancedRows,
      asOfDate: today,
    );
  },
);
