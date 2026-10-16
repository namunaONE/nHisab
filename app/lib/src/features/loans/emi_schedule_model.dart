import 'package:intl/intl.dart';

/// A single EMI installment in the amortization schedule.
class EmiInstallment {
  final int installmentNo;
  final DateTime dueDate;
  final double principalDue;
  final double interestDue;
  final double totalDue;
  final String status; // 'pending', 'paid', 'overdue'
  final DateTime? paidDate;
  final double? paidAmount;

  EmiInstallment({
    required this.installmentNo,
    required this.dueDate,
    required this.principalDue,
    required this.interestDue,
    required this.totalDue,
    required this.status,
    this.paidDate,
    this.paidAmount,
  });

  /// Whether this installment is overdue (pending and past due date).
  bool get isOverdue => status == 'pending' && dueDate.isBefore(DateTime.now());

  static final fmt = NumberFormat('#,##0.00');
}

/// Complete EMI schedule for a loan.
class EmiSchedule {
  final String loanId;
  final String partyName;
  final double principal;
  final double annualRatePct;
  final int months;
  final double emiAmount;
  final DateTime startDate;
  final String calculationMethod; // 'reducing_balance', 'daily_accrual', 'flat'
  final double totalPayable; // emiAmount * months
  final double totalInterest; // totalPayable - principal
  final List<EmiInstallment> installments;

  EmiSchedule({
    required this.loanId,
    required this.partyName,
    required this.principal,
    required this.annualRatePct,
    required this.months,
    required this.emiAmount,
    required this.startDate,
    required this.calculationMethod,
    required this.totalPayable,
    required this.totalInterest,
    required this.installments,
  });

  /// Whether this loan uses reducing-balance amortization (has a schedule).
  bool get hasSchedule =>
      calculationMethod == 'reducing_balance' || calculationMethod == 'emi';

  /// Number of pending installments.
  int get pendingCount =>
      installments.where((i) => i.status == 'pending').length;

  /// Number of overdue installments.
  int get overdueCount =>
      installments.where((i) => i.isOverdue).length;

  /// Number of paid installments.
  int get paidCount => installments.where((i) => i.status == 'paid').length;
}
