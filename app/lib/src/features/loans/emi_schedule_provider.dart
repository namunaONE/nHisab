import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../loans/loans_provider.dart';
import '../../core/calculator/loan_calculator.dart';
import 'emi_schedule_model.dart';

/// Computes the amortization schedule for a reducing-balance loan on-the-fly.
/// The emi_schedules table exists for future persistence; schedules are
/// calculated live from loan data for MVP.
final emiScheduleProvider = FutureProvider.family<EmiSchedule, String>(
  (ref, loanId) async {
    final client = Supabase.instance.client;
    final today = ref.watch(todayProvider);

    // Fetch the loan with party info
    final loanRes = await client
        .from('loans')
        .select('id, principal_amount, rate, rate_type, day_base, start_date, direction, parties(name)')
        .eq('id', loanId)
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (loanRes == null) {
      throw Exception('Loan not found: $loanId');
    }

    final principal = (loanRes['principal_amount'] as num).toDouble();
    final rate = (loanRes['rate'] as num).toDouble(); // decimal, e.g. 0.18
    final startDate = DateTime.parse(loanRes['start_date'] as String);
    final partyName = (loanRes['parties'] as Map?)?['name'] ?? '-';

    // Convert stored decimal to percentage for EMI formula
    final annualRatePct = rate * 100;

    final method = loanRes['calculation_method'] as String? ?? 'daily_accrual';
    final months = (loanRes['tenure_months'] as num?)?.toInt() ?? 12;

    // Only EMI methods get an amortization schedule
    if (method != 'reducing_balance' && method != 'flat' && method != 'emi') {
      return EmiSchedule(
        loanId: loanId,
        partyName: partyName,
        principal: principal,
        annualRatePct: annualRatePct,
        months: 0,
        emiAmount: 0,
        startDate: startDate,
        calculationMethod: method,
        totalPayable: principal,
        totalInterest: 0,
        installments: [],
      );
    }

    final installments = <EmiInstallment>[];
    double emiAmount;
    if (method == 'flat') {
      final totalInterest = principal * rate * (months / 12.0);
      emiAmount = (principal + totalInterest) / months;
      final principalPart = principal / months;
      final interestPart = totalInterest / months;
      for (int i = 1; i <= months; i++) {
        final dueDate = _addMonths(startDate, i);
        String status = dueDate.isBefore(today) ? 'overdue' : 'pending';
        installments.add(EmiInstallment(
          installmentNo: i,
          dueDate: dueDate,
          principalDue: principalPart,
          interestDue: interestPart,
          totalDue: emiAmount,
          status: status,
        ));
      }
    } else {
      emiAmount = LoanCalculator.emi(
        principal: principal,
        annualRatePct: annualRatePct,
        months: months,
      );
      double outstanding = principal;
      final monthlyRate = annualRatePct / 12 / 100;
      for (int i = 1; i <= months; i++) {
        final interest = (outstanding * monthlyRate).toDouble().clamp(0.0, emiAmount);
        final principalDue = emiAmount - interest;
        final finalPrincipal = principalDue.clamp(0.0, outstanding);
        final totalDue = emiAmount;
        final newOutstanding = outstanding - finalPrincipal;
        final dueDate = _addMonths(startDate, i);
        String status = dueDate.isBefore(today) ? 'overdue' : 'pending';
        installments.add(EmiInstallment(
          installmentNo: i,
          dueDate: dueDate,
          principalDue: finalPrincipal,
          interestDue: interest,
          totalDue: totalDue,
          status: status,
        ));
        outstanding = newOutstanding;
        if (outstanding <= 0.01) break;
      }
    }

    // Merge persisted paid status from emi_schedules table.
    try {
      final paidRows = await Supabase.instance.client
          .from('emi_schedules')
          .select('installment_no, status, paid_date, paid_amount, penalty_amount')
          .eq('loan_id', loanId)
          .filter('deleted_at', 'is', null) as List;
      final paidMap = <int, Map<String, dynamic>>{};
      for (final r in paidRows) {
        paidMap[(r['installment_no'] as num).toInt()] =
            Map<String, dynamic>.from(r);
      }
      for (var i = 0; i < installments.length; i++) {
        final inst = installments[i];
        final p = paidMap[inst.installmentNo];
        if (p != null && (p['status']?.toString() == 'paid')) {
          installments[i] = EmiInstallment(
            installmentNo: inst.installmentNo,
            dueDate: inst.dueDate,
            principalDue: inst.principalDue,
            interestDue: inst.interestDue,
            totalDue: inst.totalDue,
            status: 'paid',
            paidDate: p['paid_date'] != null
                ? DateTime.parse(p['paid_date'] as String)
                : null,
            paidAmount: (p['paid_amount'] as num?)?.toDouble(),
          );
        }
      }
    } catch (_) {
      // Keep computed schedule if DB read fails.
    }

    final totalPayable = installments.fold<double>(0, (s, e) => s + e.totalDue);
    final totalInterest = totalPayable - principal;

    return EmiSchedule(
      loanId: loanId,
      partyName: partyName,
      principal: principal,
      annualRatePct: annualRatePct,
      months: installments.length,
      emiAmount: emiAmount,
      startDate: startDate,
      calculationMethod: method,
      totalPayable: totalPayable,
      totalInterest: totalInterest,
      installments: installments,
    );
  },
);

/// Add months to a DateTime, handling month-end correctly (e.g. Jan 31 + 1mo = Feb 28).
DateTime _addMonths(DateTime date, int months) {
  final newMonth = date.month + months;
  final newYear = date.year + (newMonth - 1) ~/ 12;
  final finalMonth = ((newMonth - 1) % 12) + 1;
  final daysInMonth = DateTime(newYear, finalMonth + 1, 0).day;
  final day = date.day > daysInMonth ? daysInMonth : date.day;
  return DateTime(newYear, finalMonth, day);
}
