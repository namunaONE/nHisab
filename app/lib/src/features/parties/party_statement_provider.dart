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
        .select('*')
        .eq('party_id', partyId)
        .filter('deleted_at', 'is', null)
        .order('start_date');
    final loans = (loansRes as List);

    // Fetch only payments that belong to this party's loans. The previous
    // query fetched every payment in the tenant and then ignored the ones
    // without a matching loan, which was both wasteful and a cross-party
    // data exposure in the UI layer.
    final loanIds = loans.map((r) => r['id'] as String).toList();
    List payments = [];
    if (loanIds.isNotEmpty) {
      final paysRes = await client
          .from('payments')
          .select('*')
          .inFilter('loan_id', loanIds)
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
    double totalWrittenOff = 0;

    for (final l in loans) {
      final loanId = l['id'] as String;
      final principal = (l['principal_amount'] as num).toDouble();
      final rate = (l['rate'] as num).toDouble();
      final rateType = l['rate_type'] as String;
      final dayBase = (l['day_base'] as num?)?.toInt() ?? 360;
      final startDate = DateTime.parse(l['start_date'] as String);
      final direction = l['direction'] as String;
      final writeOff = (l['write_off_amount'] as num?)?.toDouble() ?? 0;

      totalPrincipal += principal;
      totalWrittenOff += writeOff;

      // Closed loans freeze accrual at accrual_end_date. The column is
      // introduced with the hardening migration; `*` keeps this read path
      // compatible before it is applied.
      final accrualEnd = DateTime.tryParse(
          (l['accrual_end_date'] ?? '').toString());
      final effectiveToday = accrualEnd != null && accrualEnd.isBefore(today)
          ? accrualEnd
          : today;

      // Interest accrued up to the last accrual day
      final annual = LoanCalculator.annualRate(rate: rate, rateType: rateType);
      final perDay = LoanCalculator.perDay(
          principal: principal, annualRateDecimal: annual, dayBase: dayBase);
      final dueDays =
          LoanCalculator.dueDays(start: startDate, today: effectiveToday);
      final interestAccrued = LoanCalculator.cappedInterest(
        principal: principal,
        interestAmount:
            LoanCalculator.interest(perDayAmount: perDay, dueDaysCount: dueDays),
      );
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
      final interestDue =
          LoanCalculator.dues(interest: interestAccrued, interestPaid: loanInterestPaid);
      if (interestDue > 0.01) {
        rows.add(StatementRow(
          id: 'interest-$loanId',
          date: effectiveToday,
          type: 'interest_accrual',
          description: 'Interest Accrued to Date',
          debit: direction == 'receivable' ? interestDue : 0,
          credit: direction == 'payable' ? interestDue : 0,
          balance: 0,
        ));
      }

      // A write-off is a non-cash credit that clears the remaining balance.
      // Keeping it as a statement row makes the running total reconcile with
      // the outstanding figure instead of silently disappearing.
      if (writeOff > 0.01) {
        rows.add(StatementRow(
          id: 'writeoff-$loanId',
          date: effectiveToday,
          type: 'write_off',
          description: 'Balance written off',
          debit: direction == 'payable' ? writeOff : 0,
          credit: direction == 'receivable' ? writeOff : 0,
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

    final outstanding = LoanCalculator.outstanding(
      principal: totalPrincipal,
      interest: totalInterestAccrued,
      totalPaid: totalPrincipalPaid + totalInterestPaid + totalWrittenOff,
    );

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
      totalWrittenOff: totalWrittenOff,
      outstanding: outstanding,
      rows: balancedRows,
      asOfDate: today,
    );
  },
);
