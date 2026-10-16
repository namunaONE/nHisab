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

    // Only reducing_balance loans get an amortization schedule
    final method = loanRes['calculation_method'] as String? ?? 'daily_accrual';
    if (method != 'reducing_balance' && method != 'emi') {
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

    // Fetch tenure from emi_schedules or derive from loan
    // For now, derive tenure: if loan has no explicit tenure, default to 12 months
    // In a full implementation, tenure would be stored on the loan
    final months = 12; // Default 12-month tenure for MVP

    // Compute EMI
    final emiAmount = LoanCalculator.emi(
      principal: principal,
      annualRatePct: annualRatePct,
      months: months,
    );

    // Build amortization schedule (reducing balance)
    final installments = <EmiInstallment>[];
    double outstanding = principal;
    final monthlyRate = annualRatePct / 12 / 100;

    for (int i = 1; i <= months; i++) {
      final interest = (outstanding * monthlyRate).toDouble().clamp(0.0, emiAmount);
      final principalDue = emiAmount - interest;
      final finalPrincipal = principalDue.clamp(0.0, outstanding);
      final totalDue = emiAmount;
      final newOutstanding = outstanding - finalPrincipal;

      // Due date: start_date + i months
      final dueDate = _addMonths(startDate, i);

      // Status: pending (future), overdue (past due date & unpaid)
      String status;
      if (dueDate.isBefore(today)) {
        status = 'overdue';
      } else {
        status = 'pending';
      }

      installments.add(EmiInstallment(
        installmentNo: i,
        dueDate: dueDate,
        principalDue: finalPrincipal,
        interestDue: interest,
        totalDue: totalDue,
        status: status,
      ));

      outstanding = newOutstanding;
      if (outstanding <= 0.01) break; // Loan fully paid
    }

    final totalPayable = emiAmount * installments.length;
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
